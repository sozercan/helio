import Defaults
import Foundation
import Testing
@testable import HelioKit

@MainActor
@Suite(.serialized)
struct FeedItemsManagerTests {
  private static let testCredential = RedditCredential(apiAppID: "placeholder-client-id", refreshToken: "placeholder-grant")
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

  private func makeManager(hideReadPosts: Bool, pages: [String: ([RedditEntityType], String?)]) -> (FeedItemsManager<SubListingSortOption>, () -> [String?]) {
    var requested: [String?] = []
    let manager = FeedItemsManager<SubListingSortOption>(sorting: nil, hideReadPosts: hideReadPosts, currentCredential: { Self.testCredential }, fetchFn: { after, _, _, _, _ in
      requested.append(after)
      let page = pages[after ?? "first"] ?? ([], nil)
      return (page.0, page.1)
    })
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
      await manager.reload()

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
      await manager.reload()

      #expect(requested() == [nil])
      #expect(ids(manager.entities) == ["a", "b"])
    }
  }

  @Test func keepsReadPostsInFeedsThatDontHideThem() async {
    await withHideOnRead(true) {
      let (manager, _) = makeManager(hideReadPosts: false, pages: [
        "first": ([post("a", read: true), post("b", read: true)], "p2"),
      ])
      await manager.reload()

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
      await manager.reload()

      #expect(requested().count == 6)
      #expect(manager.entities.isEmpty)
      #expect(manager.displayMode == .onlyReadPosts)

      // Continuing resumes from where the scan stopped.
      await manager.loadMore()
      #expect(requested()[6] == "p6")
    }
  }

  @Test func treatsAMissingCursorAsTheEndOfTheFeed() async {
    await withHideOnRead(false) {
      let (manager, _) = makeManager(hideReadPosts: false, pages: [
        "first": ([post("a", read: false), post("b", read: false)], nil),
      ])
      await manager.reload()

      #expect(manager.displayMode == .endOfFeed)
    }
  }

  @Test func showsEmptyFeedWhenEveryPostWasReadAndThereIsNoMore() async {
    await withHideOnRead(true) {
      let (manager, requested) = makeManager(hideReadPosts: true, pages: [
        "first": ([post("a", read: true)], nil),
      ])
      await manager.reload()

      #expect(requested() == [nil])
      #expect(manager.entities.isEmpty)
      #expect(manager.displayMode == .empty)
    }
  }

  @MainActor
  private final class ControlledFetch {
    typealias Page = (entities: [RedditEntityType]?, after: String?)?
    struct Request {
      let after: String?
      let sorting: SubListingSortOption?
      let query: String?
      let limit: Int
      let credential: RedditCredential
      let continuation: CheckedContinuation<Page, Never>
    }

    var requests: [Request] = []
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func fetch(_ after: String?, _ sorting: SubListingSortOption?, _ query: String?, _ flair: String?, _ context: FeedItemsManager<SubListingSortOption>.FetchContext) async -> Page {
      await withCheckedContinuation { continuation in
        requests.append(Request(after: after, sorting: sorting, query: query, limit: context.limit, credential: context.credential, continuation: continuation))
        let ready = waiters.filter { requests.count >= $0.count }
        waiters.removeAll { requests.count >= $0.count }
        ready.forEach { $0.continuation.resume() }
      }
    }

    func waitForRequests(_ count: Int) async {
      if requests.count >= count {
        return
      }
      await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func complete(_ index: Int, with page: Page) {
      requests[index].continuation.resume(returning: page)
    }
  }

  @Test(arguments: [false, true]) func newerRefreshOwnsTheFeedEvenWhenOlderFetchCompletes(fails: Bool) async {
    let fetch = ControlledFetch()
    let manager = FeedItemsManager<SubListingSortOption>(sorting: nil, currentCredential: { Self.testCredential }, fetchFn: fetch.fetch)
    manager.chunkSize = 2
    let old = Task { await manager.reload() }
    await fetch.waitForRequests(1)
    let new = Task { await manager.reload() }
    await fetch.waitForRequests(2)
    fetch.complete(1, with: ([post("new", read: false)], nil))
    await new.value
    fetch.complete(0, with: fails ? nil : ([post("old", read: false)], "old-cursor"))
    await old.value

    #expect(ids(manager.entities) == ["new"])
    #expect(manager.lastElementId == nil)
    #expect(manager.displayMode == .endOfFeed)
  }

  @Test func supersededPageDoesNotAppendOrReleaseTheNewRefresh() async {
    let fetch = ControlledFetch()
    let manager = FeedItemsManager<SubListingSortOption>(sorting: nil, currentCredential: { Self.testCredential }, fetchFn: fetch.fetch)
    manager.chunkSize = 2
    let first = Task { await manager.reload() }
    await fetch.waitForRequests(1)
    fetch.complete(0, with: ([post("a", read: false), post("b", read: false)], "p2"))
    await first.value
    let page = Task { await manager.loadMore() }
    await fetch.waitForRequests(2)
    let refresh = Task { await manager.reload() }
    await fetch.waitForRequests(3)
    fetch.complete(1, with: ([post("stale", read: false)], nil))
    await page.value

    // The stale page's cleanup must not let an appearing row start another request.
    manager.elementAppeared(entity: manager.entities[1])
    #expect(fetch.requests.count == 3)
    #expect(ids(manager.entities) == ["a", "b"])
    fetch.complete(2, with: ([post("fresh", read: false)], nil))
    await refresh.value
    #expect(ids(manager.entities) == ["fresh"])
  }

  @Test func appearingRowsReserveOnlyOnePageRequest() async {
    let fetch = ControlledFetch()
    let manager = FeedItemsManager<SubListingSortOption>(sorting: nil, currentCredential: { Self.testCredential }, fetchFn: fetch.fetch)
    manager.chunkSize = 2
    let first = Task { await manager.reload() }
    await fetch.waitForRequests(1)
    fetch.complete(0, with: ([post("a", read: false), post("b", read: false)], "p2"))
    await first.value
    manager.elementAppeared(entity: manager.entities[0])
    manager.elementAppeared(entity: manager.entities[1])
    await fetch.waitForRequests(2)
    #expect(fetch.requests.count == 2)
    #expect(fetch.requests[1].after == "p2")
    fetch.complete(1, with: ([post("c", read: false)], nil))
    // Join the reserved request rather than sending another one.
    await manager.loadMore()
    #expect(ids(manager.entities) == ["a", "b", "c"])
  }

  @Test func cancelledCallerDoesNotStartARequest() async {
    let fetch = ControlledFetch()
    let manager = FeedItemsManager<SubListingSortOption>(sorting: nil, currentCredential: { Self.testCredential }, fetchFn: fetch.fetch)
    let task = Task { await manager.reload() }
    task.cancel()
    await task.value
    #expect(fetch.requests.isEmpty)
  }

  @Test func hiddenPagesUseOneQuerySnapshot() async {
    await withHideOnRead(true) {
      let fetch = ControlledFetch()
      let manager = FeedItemsManager<SubListingSortOption>(sorting: nil, hideReadPosts: true, currentCredential: { Self.testCredential }, fetchFn: fetch.fetch)
      manager.chunkSize = 2
      manager.searchQuery.setNow("original")
      let task = Task { await manager.reload() }
      await fetch.waitForRequests(1)
      manager.searchQuery.setNow("changed")
      fetch.complete(0, with: ([post("a", read: true), post("b", read: true)], "p2"))
      await fetch.waitForRequests(2)
      #expect(fetch.requests.map(\.query) == ["original", "original"])
      #expect(manager.isLoadingMore)
      fetch.complete(1, with: ([post("visible", read: false)], nil))
      await task.value
      #expect(ids(manager.entities) == ["visible"])
    }
  }

  @Test func hiddenPagesKeepTheirLimitUntilTheNextRequestChain() async {
    await withHideOnRead(true) {
      let fetch = ControlledFetch()
      let manager = FeedItemsManager<SubListingSortOption>(sorting: nil, hideReadPosts: true, currentCredential: { Self.testCredential }, fetchFn: fetch.fetch)
      manager.chunkSize = 2
      let task = Task { await manager.reload() }
      await fetch.waitForRequests(1)
      manager.chunkSize = 1
      fetch.complete(0, with: ([post("a", read: true), post("b", read: true)], "p2"))
      await fetch.waitForRequests(2)
      #expect(fetch.requests.map(\.limit) == [2, 2])
      fetch.complete(1, with: ([post("c", read: true), post("d", read: true)], "p3"))
      await fetch.waitForRequests(3)
      #expect(fetch.requests.map(\.limit) == [2, 2, 2])
      fetch.complete(2, with: ([post("visible", read: false), post("also-visible", read: false)], "p4"))
      await task.value
      #expect(manager.displayMode == .items)

      let next = Task { await manager.loadMore() }
      await fetch.waitForRequests(4)
      #expect(fetch.requests[3].limit == 1)
      #expect(fetch.requests[3].after == "p4")
      fetch.complete(3, with: ([post("last", read: false)], nil))
      await next.value
      #expect(manager.displayMode == .endOfFeed)
    }
  }

  @Test(arguments: [false, true]) func aReplacedGrantCannotPublishBeforeTheViewReloads(fails: Bool) async {
    let fetch = ControlledFetch()
    var account = RedditCredential(apiAppID: "placeholder-client-id", refreshToken: "placeholder-original-grant")
    let manager = FeedItemsManager<SubListingSortOption>(sorting: nil, currentCredential: { account }, fetchFn: fetch.fetch)
    let old = Task { await manager.reload() }
    await fetch.waitForRequests(1)
    account.refreshToken = "placeholder-replacement-grant"
    fetch.complete(0, with: fails ? nil : ([post("old", read: false)], "old-cursor"))
    await old.value
    #expect(manager.entities.isEmpty)
    #expect(manager.lastElementId == nil)
    #expect(manager.displayMode == .loading)
  }

  @Test func paginationAfterSameIDReauthorizationStartsWithoutTheOldCursor() async {
    let fetch = ControlledFetch()
    var account = RedditCredential(apiAppID: "placeholder-client-id", refreshToken: "placeholder-original-grant")
    let manager = FeedItemsManager<SubListingSortOption>(sorting: nil, currentCredential: { account }, fetchFn: fetch.fetch)
    manager.chunkSize = 2
    let first = Task { await manager.reload() }
    await fetch.waitForRequests(1)
    fetch.complete(0, with: ([post("same", read: false), post("old", read: false)], "old-cursor"))
    await first.value
    account.refreshToken = "placeholder-replacement-grant"
    let next = Task { await manager.loadMore() }
    await fetch.waitForRequests(2)
    #expect(fetch.requests[1].after == nil)
    #expect(manager.entities.isEmpty)
    #expect(manager.lastElementId == nil)
    fetch.complete(1, with: ([post("same", read: false), post("new", read: false)], nil))
    await next.value
    #expect(ids(manager.entities) == ["same", "new"])
  }

  @Test func repeatedAppearanceLoadsOnlyOnce() async {
    let fetch = ControlledFetch()
    let manager = FeedItemsManager<SubListingSortOption>(sorting: nil, currentCredential: { Self.testCredential }, fetchFn: fetch.fetch)
    let first = Task { await manager.loadIfNeeded() }
    await fetch.waitForRequests(1)
    await manager.loadIfNeeded()
    #expect(fetch.requests.count == 1)
    fetch.complete(0, with: ([], nil))
    await first.value
    await manager.loadIfNeeded()
    #expect(manager.displayMode == .empty)
    #expect(fetch.requests.count == 1)
  }

  @Test func retryRestartsTheFailedFirstPage() async {
    var cursors: [String?] = []
    let manager = FeedItemsManager<SubListingSortOption>(sorting: nil, currentCredential: { Self.testCredential }, fetchFn: { after, _, _, _, _ in
      cursors.append(after)
      return cursors.count == 1 ? nil : ([self.post("a", read: false)], nil)
    })
    await manager.reload()
    #expect(manager.displayMode == .error)
    await manager.retry()
    #expect(cursors == [nil, nil])
    #expect(manager.displayMode == .endOfFeed)
    #expect(ids(manager.entities) == ["a"])
  }

  @Test func retryResumesTheFailedPageWithoutLosingExistingItems() async {
    var cursors: [String?] = []
    let manager = FeedItemsManager<SubListingSortOption>(sorting: nil, currentCredential: { Self.testCredential }, fetchFn: { after, _, _, _, _ in
      cursors.append(after)
      if after == nil {
        return ([self.post("a", read: false), self.post("b", read: false)], "p2")
      }
      return cursors.count == 2 ? nil : ([self.post("c", read: false)], nil)
    })
    manager.chunkSize = 2
    await manager.reload()
    await manager.loadMore()
    #expect(manager.displayMode == .error)
    manager.elementAppeared(entity: manager.entities[1])
    #expect(cursors == [nil, "p2"])
    await manager.retry()
    #expect(cursors == [nil, "p2", "p2"])
    #expect(ids(manager.entities) == ["a", "b", "c"])
    #expect(manager.displayMode == .endOfFeed)
  }

  @Test func clearingAFeedClearsItsCursorAndDeduplicationIndex() async {
    let fetch = ControlledFetch()
    let manager = FeedItemsManager<SubListingSortOption>(sorting: nil, currentCredential: { Self.testCredential }, fetchFn: fetch.fetch)
    manager.chunkSize = 2
    let first = Task { await manager.reload() }
    await fetch.waitForRequests(1)
    fetch.complete(0, with: ([post("a", read: false), post("b", read: false)], "p2"))
    await first.value
    let reload = Task { await manager.reload(clearItems: true) }
    await fetch.waitForRequests(2)
    #expect(manager.entities.isEmpty)
    #expect(manager.lastElementId == nil)
    #expect(manager.displayMode == .loading)
    #expect(!manager.isLoadingMore)
    fetch.complete(1, with: ([post("a", read: false)], nil))
    await reload.value
    #expect(ids(manager.entities) == ["a"])
  }
}

extension FeedItemsManagerTests {
  @Test func keepsPagingAfterAShortPageThatHasACursor() async {
    let (manager, requested) = makeManager(hideReadPosts: false, pages: [
      // Reddit may return fewer items than requested, including when decoding skips an item.
      "first": ([post("a", read: false)], "p2"),
      "p2": ([post("b", read: false), post("c", read: false)], nil),
    ])
    await manager.reload()
    #expect(manager.displayMode == .items)

    await manager.loadMore()
    #expect(requested() == [nil, "p2"])
    #expect(ids(manager.entities) == ["a", "b", "c"])
    #expect(manager.displayMode == .endOfFeed)
  }

  @Test func anEmptyPageEndsPaginationEvenIfItHasACursor() async {
    let (manager, requested) = makeManager(hideReadPosts: false, pages: [
      "first": ([post("a", read: false), post("b", read: false)], "p2"),
      "p2": ([], "p3"),
    ])
    await manager.reload()
    await manager.loadMore()
    #expect(manager.displayMode == .endOfFeed)
    await manager.loadMore()
    #expect(requested() == [nil, "p2"])
    #expect(ids(manager.entities) == ["a", "b"])
  }

  @Test func retryingAFailedQueryChangeStartsFromTheFirstPage() async {
    var newSortFails = true
    var requests: [String] = []
    let manager = FeedItemsManager<SubListingSortOption>(sorting: .hot, currentCredential: { Self.testCredential }, fetchFn: { after, sorting, _, _, _ in
      let sort = sorting == .hot ? "hot" : "new"
      requests.append("\(sort)/\(after ?? "first")")
      if sorting == .hot {
        return ([post("hot1", read: false)], "h2")
      }
      return newSortFails ? nil : ([post("new1", read: false)], "n2")
    })
    manager.chunkSize = 1
    await manager.reload()

    // A failed query change retains the old rows, but retry must not continue their cursor.
    manager.sorting = .new
    await manager.reload()
    #expect(manager.displayMode == .error)
    #expect(ids(manager.entities) == ["hot1"])
    #expect(manager.lastElementId == "h2")

    newSortFails = false
    await manager.retry()
    #expect(requests == ["hot/first", "new/first", "new/first"])
    #expect(ids(manager.entities) == ["new1"])
    #expect(manager.lastElementId == "n2")
    #expect(manager.displayMode == .items)
  }

  @Test(arguments: [false, true]) func aSupersededQueryChangeCannotReplaceTheNewList(fails: Bool) async {
    let fetch = ControlledFetch()
    let manager = FeedItemsManager<SubListingSortOption>(sorting: .hot, currentCredential: { Self.testCredential }, fetchFn: fetch.fetch)
    manager.chunkSize = 1
    let old = Task { await manager.reload() }
    await fetch.waitForRequests(1)
    manager.sorting = .new
    let new = Task { await manager.reload() }
    await fetch.waitForRequests(2)
    fetch.complete(1, with: ([post("new", read: false)], "n2"))
    await new.value
    fetch.complete(0, with: fails ? nil : ([post("old", read: false)], "h2"))
    await old.value

    #expect(fetch.requests.map(\.sorting) == [.hot, .new])
    #expect(ids(manager.entities) == ["new"])
    #expect(manager.lastElementId == "n2")
    #expect(manager.displayMode == .items)
  }

  @Test func aSupersededFirstPageDoesntFreeTheLoadMoreSlot() async {
    let fetch = ControlledFetch()
    let manager = FeedItemsManager<SubListingSortOption>(sorting: .hot, currentCredential: { Self.testCredential }, fetchFn: fetch.fetch)
    manager.chunkSize = 2
    let old = Task { await manager.reload() }
    await fetch.waitForRequests(1)
    manager.sorting = .new
    let new = Task { await manager.reload() }
    await fetch.waitForRequests(2)
    fetch.complete(1, with: ([post("a", read: false), post("b", read: false)], "p2"))
    await new.value

    manager.elementAppeared(entity: manager.entities[0])
    await fetch.waitForRequests(3)
    fetch.complete(0, with: ([post("old", read: false)], "h2"))
    await old.value

    // The obsolete first page's cleanup cannot release the current page reservation.
    manager.elementAppeared(entity: manager.entities[1])
    #expect(fetch.requests.count == 3)
    #expect(fetch.requests[2].after == "p2")
    #expect(fetch.requests[2].sorting == .new)
    fetch.complete(2, with: ([post("c", read: false)], "p3"))
    await manager.loadMore()
    #expect(fetch.requests.count == 3)
    #expect(ids(manager.entities) == ["a", "b", "c"])
  }

  @Test func holdsLoadMoreUntilTheNewFirstPageLands() async {
    let fetch = ControlledFetch()
    let manager = FeedItemsManager<SubListingSortOption>(sorting: nil, currentCredential: { Self.testCredential }, fetchFn: fetch.fetch)
    manager.chunkSize = 1
    let first = Task { await manager.reload() }
    await fetch.waitForRequests(1)
    fetch.complete(0, with: ([post("a", read: false)], "p2"))
    await first.value

    let refresh = Task { await manager.reload() }
    await fetch.waitForRequests(2)
    manager.elementAppeared(entity: manager.entities[0])
    manager.elementAppeared(entity: manager.entities[0])
    // Rows still on screen must not fetch the old cursor while refreshing.
    #expect(fetch.requests.map(\.after) == [nil, nil])
    #expect(ids(manager.entities) == ["a"])

    // The same row stays on screen, so no new appearance should be needed to continue.
    fetch.complete(1, with: ([post("a", read: false)], "q2"))
    await fetch.waitForRequests(3)
    #expect(fetch.requests.map(\.after) == [nil, nil, "q2"])
    fetch.complete(2, with: ([post("c", read: false)], nil))
    await refresh.value
    await manager.loadMore()
    #expect(fetch.requests.count == 3)
    #expect(ids(manager.entities) == ["a", "c"])
    #expect(manager.displayMode == .endOfFeed)
  }

  @Test(arguments: [false, true]) func aRefreshCarriesOverTheLoadMoreItReplaces(fails: Bool) async {
    let fetch = ControlledFetch()
    let manager = FeedItemsManager<SubListingSortOption>(sorting: .hot, currentCredential: { Self.testCredential }, fetchFn: fetch.fetch)
    manager.chunkSize = 1
    let first = Task { await manager.reload() }
    await fetch.waitForRequests(1)
    fetch.complete(0, with: ([post("a", read: false)], "p2"))
    await first.value
    let oldPage = Task { await manager.loadMore() }
    await fetch.waitForRequests(2)

    manager.sorting = .new
    let refresh = Task { await manager.reload() }
    await fetch.waitForRequests(3)
    // Live settings can change again; the handoff belongs to the refreshed list's query.
    manager.sorting = .hot
    fetch.complete(2, with: ([post("a", read: false)], "q2"))
    await fetch.waitForRequests(4)
    #expect(fetch.requests.map(\.after) == [nil, "p2", nil, "q2"])
    #expect(fetch.requests.map(\.sorting) == [.hot, .hot, .new, .new])
    fetch.complete(3, with: ([post("c", read: false)], nil))
    await refresh.value
    await manager.loadMore()

    // Cancellation is cooperative: the replaced page may still return data or an error.
    fetch.complete(1, with: fails ? nil : ([post("stale", read: false)], "p3"))
    await oldPage.value
    #expect(fetch.requests.count == 4)
    #expect(ids(manager.entities) == ["a", "c"])
    #expect(manager.lastElementId == nil)
    #expect(manager.displayMode == .endOfFeed)
  }

  @Test func aLoadMoreCancelledBeforeItStartsFetchesNothing() async {
    let (manager, requested) = makeManager(hideReadPosts: false, pages: [
      "first": ([post("a", read: false), post("b", read: false)], "p2"),
    ])
    await manager.reload()
    let loadMore = Task { await manager.loadMore() }
    loadMore.cancel()
    await loadMore.value
    #expect(requested() == [nil])
    #expect(manager.displayMode == .items)
  }

  @Test func loadingMoreUsesTheQueryTheListWasFetchedWith() async {
    let fetch = ControlledFetch()
    let manager = FeedItemsManager<SubListingSortOption>(sorting: .hot, currentCredential: { Self.testCredential }, fetchFn: fetch.fetch)
    manager.chunkSize = 1
    manager.searchQuery.setNow("original")
    let first = Task { await manager.reload() }
    await fetch.waitForRequests(1)
    fetch.complete(0, with: ([post("a", read: false)], "h2"))
    await first.value

    // The controls changed, but the shown list has not reloaded yet.
    manager.sorting = .new
    manager.searchQuery.setNow("changed")
    manager.chunkSize = 2
    let next = Task { await manager.loadMore() }
    await fetch.waitForRequests(2)
    #expect(fetch.requests.map(\.after) == [nil, "h2"])
    #expect(fetch.requests.map(\.sorting) == [.hot, .hot])
    #expect(fetch.requests.map(\.query) == ["original", "original"])
    #expect(fetch.requests.map(\.limit) == [1, 2])
    fetch.complete(1, with: ([post("b", read: false)], "h3"))
    await next.value
    #expect(ids(manager.entities) == ["a", "b"])
    #expect(manager.displayMode == .items)
  }

  @Test func changingTheQueryLeavesTheSpinnerToTheReload() async {
    let (manager, _) = makeManager(hideReadPosts: false, pages: [
      "first": ([post("a", read: false), post("b", read: false)], "p2"),
    ])
    manager.sorting = .hot
    await manager.reload()
    #expect(manager.displayMode == .items)

    // Re-selecting or flipping the sort starts no request, so it must not show a spinner.
    manager.sorting = .hot
    manager.sorting = .new
    manager.sorting = .hot
    #expect(manager.displayMode == .items)
  }
}

extension FeedItemsManagerTests {
  @Test func signedOutRequestsFailWithoutCallingTheAdapter() async {
    var dispatched = false
    let manager = FeedItemsManager<SubListingSortOption>(sorting: nil, currentCredential: { nil }, fetchFn: { _, _, _, _, _ in
      dispatched = true
      return ([], nil)
    })
    await manager.reload()
    #expect(!dispatched)
    #expect(manager.displayMode == .error)
    #expect(manager.entities.isEmpty && manager.lastElementId == nil)
  }

  @Test func pageChainsCaptureTheCurrentTokenWithoutChangingAuthorization() async {
    let fetch = ControlledFetch()
    var account = Self.testCredential
    let manager = FeedItemsManager<SubListingSortOption>(sorting: nil, currentCredential: { account }, fetchFn: fetch.fetch)
    let first = Task { await manager.reload() }
    await fetch.waitForRequests(1)
    fetch.complete(0, with: ([post("first", read: false)], "p2"))
    await first.value
    account.accessToken = .init(token: "placeholder-renewed-token", expiration: 3600, lastRefresh: Date())
    let next = Task { await manager.loadMore() }
    await fetch.waitForRequests(2)
    #expect(fetch.requests[1].after == "p2")
    #expect(fetch.requests[1].credential.accessToken?.token == "placeholder-renewed-token")
    #expect(fetch.requests[1].credential.authorizationID == fetch.requests[0].credential.authorizationID)
    fetch.complete(1, with: ([post("second", read: false)], nil))
    await next.value
    #expect(ids(manager.entities) == ["first", "second"])
  }
}

extension FeedItemsManagerTests {
  @Test(arguments: [false, true]) func nonClearingRefreshKeepsRowsVisibleUntilItFinishes(fails: Bool) async {
    let fetch = ControlledFetch()
    let manager = FeedItemsManager<SubListingSortOption>(sorting: nil, currentCredential: { Self.testCredential }, fetchFn: fetch.fetch)
    let first = Task { await manager.reload() }
    await fetch.waitForRequests(1)
    fetch.complete(0, with: ([post("visible", read: false)], nil))
    await first.value
    let refresh = Task { await manager.reload(clearItems: false) }
    await fetch.waitForRequests(2)
    #expect(ids(manager.entities) == ["visible"])
    #expect(manager.displayMode == .items)
    fetch.complete(1, with: fails ? nil : ([post("replacement", read: false)], nil))
    await refresh.value
    #expect(ids(manager.entities) == (fails ? ["visible"] : ["replacement"]))
    #expect(manager.displayMode == (fails ? .error : .endOfFeed))
  }
}
