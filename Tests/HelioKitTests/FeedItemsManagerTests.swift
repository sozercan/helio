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

  @Test func pickingTheCurrentSortAgainKeepsTheFeed() async {
    await withHideOnRead(false) {
      let manager = FeedItemsManager<SubListingSortOption>(sorting: .hot) { _, _, _, _ in ([post("a", read: false)], "p2") }
      manager.chunkSize = 1
      await manager.fetchCaller(loadingMore: false)
      #expect(manager.displayMode == .items)

      // No reload follows an unchanged sort, so a spinner here would never go away.
      manager.sorting = .hot
      #expect(manager.displayMode == .items)

      manager.sorting = .new
      #expect(manager.displayMode == .loading)
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
