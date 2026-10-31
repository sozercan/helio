import Defaults
import Foundation
import Testing
@testable import HelioKit

@MainActor
@Suite(.serialized)
struct FeedItemsManagerTests {
  /// `PostData`'s ids are constants, so re-key the sample post through its Codable form.
  private func post(_ id: String, read: Bool) -> RedditEntityType {
    var json = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(postSampleData)) as! [String: Any]
    json["id"] = id
    json["name"] = "t3_\(id)"
    var data = try! JSONDecoder().decode(PostData.self, from: JSONSerialization.data(withJSONObject: json))
    data.helioSeen = read
    let post = Post(id: id)
    post.data = data
    return .post(post)
  }

  private func ids(_ entities: [RedditEntityType]) -> [String] {
    entities.compactMap {
      if case let .post(post) = $0 {
        post.data?.id
      } else {
        nil
      }
    }
  }

  /// Long enough for a load-more that shouldn't exist to reach the fetch function.
  private func letStrayRequestsStart() async {
    try? await Task.sleep(for: .milliseconds(200))
  }

  /// `fetchPage` appends later pages on the main queue; let those blocks run.
  private func drainMainQueue() async {
    await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
  }

  private func makeManager(hideReadPosts: Bool, pages: [String: ([RedditEntityType], String?)]) -> (FeedItemsManager<SubListingSortOption>, () -> [String?]) {
    var requested: [String?] = []
    let manager = FeedItemsManager<SubListingSortOption>(sorting: nil, hideReadPosts: hideReadPosts) { after, _, _, _ in
      requested.append(after)
      let page = pages[after ?? "first"] ?? ([], nil)
      return (page.0, page.1)
    }
    manager.chunkSize = 2
    return (manager, { requested })
  }

  private func withHideOnRead(_ enabled: Bool, _ body: () async -> Void) async {
    let previous = Defaults[.PostLinkDefSettings].hideOnRead
    Defaults[.PostLinkDefSettings].hideOnRead = enabled
    await body()
    Defaults[.PostLinkDefSettings].hideOnRead = previous
  }

  @Test func skipsPagesWhosePostsWereAllRead() async {
    await withHideOnRead(true) {
      let (manager, requested) = makeManager(hideReadPosts: true, pages: [
        "first": ([post("a", read: true), post("b", read: true)], "p2"),
        "p2": ([post("c", read: true), post("d", read: false)], "p3"),
      ])
      await manager.fetchCaller(loadingMore: false)
      await drainMainQueue()

      #expect(requested() == [nil, "p2"])
      #expect(ids(manager.entities) == ["d"])
      #expect(manager.lastElementId == "p3")
      #expect(manager.displayMode == .items)
    }
  }

  @Test func keepsReadPostsWhenSettingIsOff() async {
    await withHideOnRead(false) {
      let (manager, requested) = makeManager(hideReadPosts: true, pages: [
        "first": ([post("a", read: true), post("b", read: false)], "p2"),
      ])
      await manager.fetchCaller(loadingMore: false)

      #expect(requested() == [nil])
      #expect(ids(manager.entities) == ["a", "b"])
    }
  }

  @Test func keepsReadPostsInFeedsThatDontHideThem() async {
    await withHideOnRead(true) {
      let (manager, _) = makeManager(hideReadPosts: false, pages: [
        "first": ([post("a", read: true), post("b", read: true)], "p2"),
      ])
      await manager.fetchCaller(loadingMore: false)

      #expect(ids(manager.entities) == ["a", "b"])
    }
  }

  @Test func offersToContinueAfterTooManyPagesOfReadPosts() async {
    await withHideOnRead(true) {
      var pages: [String: ([RedditEntityType], String?)] = [:]
      for i in 0 ..< 10 {
        pages[i == 0 ? "first" : "p\(i)"] = ([post("a\(i)", read: true), post("b\(i)", read: true)], "p\(i + 1)")
      }
      let (manager, requested) = makeManager(hideReadPosts: true, pages: pages)
      await manager.fetchCaller(loadingMore: false)
      await drainMainQueue()

      #expect(requested().count == 6)
      #expect(manager.entities.isEmpty)
      #expect(manager.displayMode == .onlyReadPosts)

      // Continuing resumes from where the scan stopped.
      await manager.fetchCaller(loadingMore: true)
      await drainMainQueue()
      #expect(requested()[6] == "p6")
    }
  }

  @Test func treatsAMissingCursorAsTheEndOfTheFeed() async {
    await withHideOnRead(false) {
      let (manager, _) = makeManager(hideReadPosts: false, pages: [
        "first": ([post("a", read: false), post("b", read: false)], nil),
      ])
      await manager.fetchCaller(loadingMore: false)

      #expect(manager.displayMode == .endOfFeed)
    }
  }

  @Test func showsEmptyFeedWhenEveryPostWasReadAndThereIsNoMore() async {
    await withHideOnRead(true) {
      let (manager, requested) = makeManager(hideReadPosts: true, pages: [
        "first": ([post("a", read: true)], nil),
      ])
      await manager.fetchCaller(loadingMore: false)

      #expect(requested() == [nil])
      #expect(manager.entities.isEmpty)
      #expect(manager.displayMode == .empty)
    }
  }

  /// First-page fetches sorted by `.hot` wait on `gate`; `.new` returns `newPage` right away.
  private func makeGatedManager(gate: Gate, hotPage: ([RedditEntityType], String?)?, newPage: ([RedditEntityType], String?)?) -> FeedItemsManager<SubListingSortOption> {
    let manager = FeedItemsManager<SubListingSortOption>(sorting: nil) { _, sorting, _, _ in
      if sorting == .hot {
        await gate.wait()
        return hotPage
      }
      return newPage
    }
    manager.chunkSize = 1
    return manager
  }

  @Test func dropsAFirstPageThatLandsAfterANewerOne() async {
    await withHideOnRead(false) {
      let gate = Gate()
      let manager = makeGatedManager(gate: gate, hotPage: ([post("old", read: false)], "h2"), newPage: ([post("new", read: false)], "n2"))
      manager.sorting = .hot
      let slow = Task { await manager.fetchCaller(loadingMore: false) }
      await gate.untilWaiting()

      // The sort changes while the first page is still loading.
      manager.sorting = .new
      await manager.fetchCaller(loadingMore: false)
      #expect(ids(manager.entities) == ["new"])

      await gate.open()
      await slow.value
      #expect(ids(manager.entities) == ["new"])
      #expect(manager.lastElementId == "n2")
      #expect(manager.displayMode == .items)
    }
  }

  @Test func dropsAnErrorFromASupersededFetch() async {
    await withHideOnRead(false) {
      let gate = Gate()
      let manager = makeGatedManager(gate: gate, hotPage: nil, newPage: ([post("new", read: false)], "n2"))
      manager.sorting = .hot
      let slow = Task { await manager.fetchCaller(loadingMore: false) }
      await gate.untilWaiting()

      manager.sorting = .new
      await manager.fetchCaller(loadingMore: false)
      await gate.open()
      await slow.value

      #expect(manager.displayMode == .items)
      #expect(ids(manager.entities) == ["new"])
    }
  }

  @Test func dropsALoadMorePageAfterTheFeedWasRefreshed() async {
    await withHideOnRead(false) {
      let gate = Gate()
      var refreshed = false
      let manager = FeedItemsManager<SubListingSortOption>(sorting: nil) { after, _, _, _ in
        if after == "p2" {
          await gate.wait()
          return ([post("stale", read: false)], "p3")
        }
        return refreshed ? ([post("b", read: false)], "q2") : ([post("a", read: false)], "p2")
      }
      manager.chunkSize = 1
      await manager.fetchCaller(loadingMore: false)
      #expect(ids(manager.entities) == ["a"])

      let loadMore = Task { await manager.fetchCaller(loadingMore: true) }
      await gate.untilWaiting()

      refreshed = true
      await manager.fetchCaller(loadingMore: false)
      await gate.open()
      await loadMore.value

      #expect(ids(manager.entities) == ["b"])
      #expect(manager.lastElementId == "q2")
    }
  }

  @Test func dropsALoadMoreStartedWhileARefreshIsPending() async {
    await withHideOnRead(false) {
      let refreshGate = Gate()
      let loadMoreGate = Gate()
      var refreshing = false
      let manager = FeedItemsManager<SubListingSortOption>(sorting: nil) { after, _, _, _ in
        if after == "p2" {
          await loadMoreGate.wait()
          return ([post("stale", read: false)], "p3")
        }
        if refreshing {
          await refreshGate.wait()
          return ([post("b", read: false)], "q2")
        }
        return ([post("a", read: false)], "p2")
      }
      manager.chunkSize = 1
      await manager.fetchCaller(loadingMore: false)

      // Pull to refresh; the old rows stay on screen and ask for the next page meanwhile.
      refreshing = true
      let refresh = Task { await manager.fetchCaller(loadingMore: false) }
      await refreshGate.untilWaiting()
      let loadMore = Task { await manager.fetchCaller(loadingMore: true) }
      await loadMoreGate.untilWaiting()

      await refreshGate.open()
      await refresh.value
      await loadMoreGate.open()
      await loadMore.value

      #expect(ids(manager.entities) == ["b"])
      #expect(manager.lastElementId == "q2")
    }
  }

  @Test func keepsPagingAfterAShortPageThatHasACursor() async {
    await withHideOnRead(false) {
      let (manager, requested) = makeManager(hideReadPosts: false, pages: [
        // One item short of a chunk, as when Reddit returns fewer or one fails to decode.
        "first": ([post("a", read: false)], "p2"),
        "p2": ([post("b", read: false), post("c", read: false)], nil),
      ])
      await manager.fetchCaller(loadingMore: false)
      #expect(manager.displayMode == .items)

      await manager.fetchCaller(loadingMore: true)
      #expect(requested() == [nil, "p2"])
      #expect(ids(manager.entities) == ["a", "b", "c"])
      #expect(manager.displayMode == .endOfFeed)
    }
  }

  @Test func reloadingAfterAFailedFirstPageAppliesItsPage() async {
    await withHideOnRead(false) {
      var fail = true
      let manager = FeedItemsManager<SubListingSortOption>(sorting: nil) { _, _, _, _ in
        fail ? nil : ([post("a", read: false)], "p2")
      }
      await manager.fetchCaller(loadingMore: false)
      #expect(manager.displayMode == .error)

      // The error row's reload button.
      fail = false
      await manager.retry()
      #expect(ids(manager.entities) == ["a"])
    }
  }

  @Test func retryingAFailedQueryChangeStartsFromTheFirstPage() async {
    await withHideOnRead(false) {
      var newSortFails = true
      var requests: [String] = []
      let manager = FeedItemsManager<SubListingSortOption>(sorting: .hot) { after, sorting, _, _ in
        let sort = sorting == .hot ? "hot" : "new"
        requests.append("\(sort)/\(after ?? "first")")
        if sorting == .hot {
          return ([post("hot1", read: false)], "h2")
        }
        return newSortFails ? nil : ([post("new1", read: false)], "n2")
      }
      await manager.fetchCaller(loadingMore: false)

      // The sort changes and its first page fails; the old sort's rows stay under the error row.
      manager.sorting = .new
      await manager.fetchCaller(loadingMore: false)
      #expect(manager.displayMode == .error)

      newSortFails = false
      await manager.retry()
      #expect(requests == ["hot/first", "new/first", "new/first"])
      #expect(ids(manager.entities) == ["new1"])
      #expect(manager.lastElementId == "n2")
    }
  }

  @Test func retryingAFailedLoadMoreContinuesTheList() async {
    await withHideOnRead(false) {
      var nextPageFails = true
      var requests: [String?] = []
      let manager = FeedItemsManager<SubListingSortOption>(sorting: nil) { after, _, _, _ in
        requests.append(after)
        if after == "p2" {
          return nextPageFails ? nil : ([post("b", read: false)], nil)
        }
        return ([post("a", read: false)], "p2")
      }
      await manager.fetchCaller(loadingMore: false)
      await manager.fetchCaller(loadingMore: true)
      #expect(manager.displayMode == .error)

      nextPageFails = false
      await manager.retry()
      #expect(requests == [nil, "p2", "p2"])
      #expect(ids(manager.entities) == ["a", "b"])
    }
  }

  @Test func aSupersededFirstPageDoesntFreeTheLoadMoreSlot() async {
    await withHideOnRead(false) {
      let slowFirstPage = Gate()
      let nextPage = Gate()
      var nextPageRequests = 0
      let manager = FeedItemsManager<SubListingSortOption>(sorting: .hot) { after, sorting, _, _ in
        if after == "p2" {
          nextPageRequests += 1
          if nextPageRequests == 1 {
            await nextPage.wait()
          }
          return ([post("c", read: false)], "p3")
        }
        if sorting == .hot {
          await slowFirstPage.wait()
          return ([post("old", read: false)], "h2")
        }
        return ([post("a", read: false), post("b", read: false)], "p2")
      }
      manager.chunkSize = 2
      let slow = Task { await manager.fetchCaller(loadingMore: false) }
      await slowFirstPage.untilWaiting()
      manager.sorting = .new
      await manager.fetchCaller(loadingMore: false)

      // A row appears and starts loading the next page, then the old first page lands.
      manager.elementAppeared(entity: manager.entities[0])
      await nextPage.untilWaiting()
      await slowFirstPage.open()
      await slow.value

      // Another row appearing must not ask for the same page again.
      manager.elementAppeared(entity: manager.entities[1])
      await letStrayRequestsStart()
      #expect(nextPageRequests == 1)
      await nextPage.open()
    }
  }

  @Test func holdsLoadMoreUntilTheNewFirstPageLands() async {
    await withHideOnRead(false) {
      let refreshGate = Gate()
      var refreshing = false
      var requests: [String?] = []
      let manager = FeedItemsManager<SubListingSortOption>(sorting: nil) { after, _, _, _ in
        requests.append(after)
        switch after {
        case "p2": return ([post("stale", read: false)], "p3")
        case "q2": return ([post("c", read: false)], nil)
        default: break
        }
        if refreshing {
          await refreshGate.wait()
          // The same post as before, so its row stays on screen and doesn't appear again.
          return ([post("a", read: false)], "q2")
        }
        return ([post("a", read: false)], "p2")
      }
      manager.chunkSize = 1
      await manager.fetchCaller(loadingMore: false)

      refreshing = true
      let refresh = Task { await manager.fetchCaller(loadingMore: false) }
      await refreshGate.untilWaiting()
      manager.elementAppeared(entity: manager.entities[0])
      await letStrayRequestsStart()
      // Nothing continues the old list while the new first page is pending.
      #expect(requests == [nil, nil])

      await refreshGate.open()
      await refresh.value
      await letStrayRequestsStart()

      // Once it lands, the held-back load-more continues the new list.
      #expect(requests == [nil, nil, "q2"])
      #expect(ids(manager.entities) == ["a", "c"])
    }
  }

  @Test func loadingMoreUsesTheQueryTheListWasFetchedWith() async {
    await withHideOnRead(false) {
      var requests: [String] = []
      let manager = FeedItemsManager<SubListingSortOption>(sorting: .hot) { after, sorting, _, _ in
        requests.append("\(sorting == .hot ? "hot" : "new")/\(after ?? "first")")
        return after == nil ? ([post("a", read: false)], "h2") : ([post("b", read: false)], "h3")
      }
      await manager.fetchCaller(loadingMore: false)

      // The sort changed, but the feed hasn't reloaded yet when the shown list asks for more.
      manager.sorting = .new
      await manager.fetchCaller(loadingMore: true)

      #expect(requests == ["hot/first", "hot/h2"])
      #expect(ids(manager.entities) == ["a", "b"])
    }
  }

  @Test func changingTheQueryLeavesTheSpinnerToTheReload() async {
    await withHideOnRead(false) {
      let manager = FeedItemsManager<SubListingSortOption>(sorting: .hot) { _, _, _, _ in ([post("a", read: false)], "p2") }
      manager.chunkSize = 1
      await manager.fetchCaller(loadingMore: false)
      #expect(manager.displayMode == .items)

      // Re-picking the sort, or flipping it away and back before the feed reloads, starts no
      // reload, so a spinner set here would never go away. The feed's reload sets it instead.
      manager.sorting = .hot
      manager.sorting = .new
      manager.sorting = .hot
      #expect(manager.displayMode == .items)
    }
  }

  @Test func showsAnErrorWhenTheFirstPageFails() async {
    let manager = FeedItemsManager<SubListingSortOption>(sorting: nil) { _, _, _, _ in nil }
    await manager.fetchCaller(loadingMore: false)

    #expect(manager.displayMode == .error)
  }
}

/// Holds one fetch until the test opens it.
private actor Gate {
  private var held: CheckedContinuation<Void, Never>?
  private var waitingForHold: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    await withCheckedContinuation { continuation in
      held = continuation
      waitingForHold.forEach { $0.resume() }
      waitingForHold = []
    }
  }

  /// Returns once a fetch is held at the gate.
  func untilWaiting() async {
    if held != nil {
      return
    }
    await withCheckedContinuation { waitingForHold.append($0) }
  }

  func open() {
    held?.resume()
    held = nil
  }
}
