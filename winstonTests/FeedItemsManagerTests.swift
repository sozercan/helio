import Foundation
import Testing
import Defaults
@testable import winston

@MainActor
@Suite(.serialized)
struct FeedItemsManagerTests {
  /// `PostData`'s ids are constants, so re-key the sample post through its Codable form.
  private func post(_ id: String, read: Bool) -> RedditEntityType {
    var json = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(postSampleData)) as! [String: Any]
    json["id"] = id
    json["name"] = "t3_\(id)"
    var data = try! JSONDecoder().decode(PostData.self, from: JSONSerialization.data(withJSONObject: json))
    data.winstonSeen = read
    let post = Post(id: id)
    post.data = data
    return .post(post)
  }

  private func ids(_ entities: [RedditEntityType]) -> [String] {
    entities.compactMap { if case .post(let post) = $0 { post.data?.id } else { nil } }
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
      for i in 0..<10 {
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
}
