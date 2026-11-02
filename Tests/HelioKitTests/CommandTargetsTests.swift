import Testing
@testable import HelioKit

struct CommandTargetsTests {
  private func posts(_ ids: [String]) -> [Post] {
    ids.map { Post(id: $0, subID: "apple") }
  }

  @Test func nextAndPreviousPostFollowTheFeed() {
    let feed = posts(["a", "b", "c"])
    let open = feed[1].id
    #expect(CommandTargets.post(1, from: open, in: feed)?.id == feed[2].id)
    #expect(CommandTargets.post(-1, from: open, in: feed)?.id == feed[0].id)
  }

  @Test func thereIsNoPostPastTheFeedsEnds() {
    let feed = posts(["a", "b"])
    #expect(CommandTargets.post(-1, from: feed[0].id, in: feed) == nil)
    #expect(CommandTargets.post(1, from: feed[1].id, in: feed) == nil)
  }

  @Test func aPostThatIsNotInTheFeedHasNoNeighbors() {
    let feed = posts(["a", "b"])
    #expect(CommandTargets.post(1, from: Post(id: "z", subID: "apple").id, in: feed) == nil)
  }

  @Test func refreshActsOnTheScreenShownLast() {
    let targets = CommandTargets()
    var refreshed: [String] = []
    _ = targets.register(.init(kind: .subs, refresh: { refreshed.append("subs") }))
    let feed = targets.register(.init(kind: .feed, column: .feed, refresh: { refreshed.append("feed") }))
    let post = targets.register(.init(kind: .post, column: .post, refresh: { refreshed.append("post") }))
    targets.refresh()
    targets.unregister(post)
    targets.refresh()
    targets.unregister(feed)
    targets.refresh()
    #expect(refreshed == ["post", "feed", "subs"])
  }

  @Test func refreshIsUnavailableWithNothingToRefresh() {
    let targets = CommandTargets()
    #expect(!targets.canRefresh)
    let search = targets.register(.init(kind: .search, focusSearch: {}))
    #expect(!targets.canRefresh)
    targets.unregister(search)
    _ = targets.register(.init(kind: .feed, refresh: {}))
    #expect(targets.canRefresh)
  }

  @Test func findFocusesTheSearchFieldShownLast() {
    let targets = CommandTargets()
    var focused: [String] = []
    _ = targets.register(.init(kind: .subs, focusSearch: { focused.append("subs") }))
    let feed = targets.register(.init(kind: .feed, focusSearch: { focused.append("feed") }))
    // A post has no search field, so Find skips it.
    _ = targets.register(.init(kind: .post, post: Post(id: "a", subID: "apple")))
    targets.find()
    targets.unregister(feed)
    targets.find()
    #expect(focused == ["feed", "subs"])
    #expect(!targets.takeSearchFocusRequest())
  }

  @Test func theOpenPostIsThePostShownLast() {
    let targets = CommandTargets()
    let first = Post(id: "a", subID: "apple")
    let second = Post(id: "b", subID: "apple")
    let a = targets.register(.init(kind: .post, post: first))
    _ = targets.register(.init(kind: .feed, refresh: {}))
    #expect(targets.openPost?.post === first)
    let b = targets.register(.init(kind: .post, post: second))
    #expect(targets.openPost?.post === second)
    targets.unregister(b)
    targets.unregister(a)
    #expect(targets.openPost == nil)
  }
}
