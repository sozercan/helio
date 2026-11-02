import Foundation
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

struct AdjacentPostTests {
  private let feed = ["a", "b", "c"].map { Post(id: $0, subID: "apple") }
  private let home = Router.NavDest.reddit(.subFeed(Subreddit(id: "home")))
  private let profile = Router.NavDest.reddit(.user(User(id: "someone")))

  /// The posts tab with `feed` as its feed and the post at `open` in the post column.
  private func router(open: Int, columns: Bool, above: [Router.NavDest] = []) -> Router {
    let router = Router(id: "test")
    router.firstIsSidebarSelection = columns
    router.fullPath = [home, .reddit(.post(feed[open]))] + above
    return router
  }

  @Test func theFeedsPostsStayAvailableWhileItsPostCoversIt() {
    let targets = CommandTargets()
    let registration = targets.register(.init(kind: .feed, column: .feed, posts: { feed }))
    // Collapsed into one stack, the open post hides the feed.
    targets.unregister(registration)
    let router = router(open: 1, columns: false)
    #expect(targets.adjacentPost(1, in: router)?.id == feed[2].id)
    #expect(targets.adjacentPost(-1, in: router)?.id == feed[0].id)
  }

  @Test func onlyAFeedThatShowsScrollsToThePostItOpens() {
    let targets = CommandTargets()
    var reveals = 0
    var target = CommandTargets.Target(kind: .feed, column: .feed, posts: { feed })
    target.reveal = { _ in reveals += 1 }
    let registration = targets.register(target)
    let router = router(open: 0, columns: true)
    targets.openAdjacentPost(1, in: router)
    #expect(router.postColumn.first?.id == feed[1].id)
    #expect(reveals == 1)
    targets.unregister(registration)
    targets.openAdjacentPost(1, in: router)
    #expect(router.postColumn.first?.id == feed[2].id)
    #expect(reveals == 1)
  }

  @Test func besideTheFeedNextFollowsTheMarkedPostUnderScreensOpenedFromIt() {
    #expect(CommandTargets.feedPostID(in: router(open: 1, columns: true, above: [profile])) == feed[1].id)
  }

  @Test func inOneStackOnlyThePostItselfMoves() {
    #expect(CommandTargets.feedPostID(in: router(open: 1, columns: false)) == feed[1].id)
    #expect(CommandTargets.feedPostID(in: router(open: 1, columns: false, above: [profile])) == nil)
    #expect(CommandTargets.feedPostID(in: router(open: 1, columns: false, above: [.reddit(.post(feed[2]))])) == nil)
  }

  @Test func withNoPostOpenThereIsNothingToMoveFrom() {
    let router = Router(id: "test")
    router.fullPath = [home]
    #expect(CommandTargets.feedPostID(in: router) == nil)
  }

  @Test func nextPastTheLoadedPostsLoadsTheNextPageAndOpensItsFirstPost() async {
    let targets = CommandTargets()
    var loaded = feed
    let more = Post(id: "d", subID: "apple")
    let registration = targets.register(.init(kind: .feed, column: .feed, posts: { loaded }, canLoadMore: { true }, loadMore: { loaded.append(more) }))
    // Collapsed into one stack, the open post covers the feed, so its rows can't page it.
    targets.unregister(registration)
    let router = router(open: 2, columns: false)
    #expect(targets.adjacentPost(1, in: router) == nil)
    #expect(targets.canOpenAdjacentPost(1, in: router))
    await targets.openAdjacentPost(1, in: router)?.value
    #expect(router.postColumn.first?.id == more.id)
  }

  @Test func nextStopsAtTheEndOfTheFeed() {
    let targets = CommandTargets()
    _ = targets.register(.init(kind: .feed, column: .feed, posts: { feed }, canLoadMore: { false }, loadMore: {}))
    let router = router(open: 2, columns: false)
    #expect(!targets.canOpenAdjacentPost(1, in: router))
    #expect(targets.openAdjacentPost(1, in: router) == nil)
    // Previous never loads a page.
    _ = targets.register(.init(kind: .feed, column: .feed, posts: { feed }, canLoadMore: { true }, loadMore: {}))
    #expect(!targets.canOpenAdjacentPost(-1, in: self.router(open: 0, columns: false)))
  }

  @Test func aPageThatArrivesAfterTheUserMovedOnDoesntOpenAPost() async {
    let targets = CommandTargets()
    var loaded = feed
    let router = router(open: 2, columns: false)
    _ = targets.register(.init(kind: .feed, column: .feed, posts: { loaded }, canLoadMore: { true }, loadMore: {
      loaded.append(Post(id: "d", subID: "apple"))
      router.closePost()
    }))
    await targets.openAdjacentPost(1, in: router)?.value
    #expect(router.postColumn.isEmpty)
  }

  @Test func aReplyStartedWhileThePageLoadsKeepsItsPost() async {
    let targets = CommandTargets()
    var loaded = feed
    _ = targets.register(.init(kind: .feed, column: .feed, posts: { loaded }, canLoadMore: { true }, loadMore: {
      loaded.append(Post(id: "d", subID: "apple"))
      _ = targets.register(.init(kind: .modal))
    }))
    let router = router(open: 2, columns: false)
    await targets.openAdjacentPost(1, in: router)?.value
    #expect(router.postColumn.first?.id == feed[2].id)
  }

  @Test func aScreenOpenedOverThePostWhileThePageLoadsStays() async {
    let targets = CommandTargets()
    var loaded = feed
    let router = router(open: 2, columns: true)
    _ = targets.register(.init(kind: .feed, column: .feed, posts: { loaded }, canLoadMore: { true }, loadMore: {
      loaded.append(Post(id: "d", subID: "apple"))
      router.navigateTo(profile, from: .post)
    }))
    await targets.openAdjacentPost(1, in: router)?.value
    #expect(router.fullPath == [home, .reddit(.post(feed[2])), profile])
  }

  @Test func anotherFeedChosenWhileThePageLoadsKeepsThePost() async {
    let targets = CommandTargets()
    var loaded = feed
    _ = targets.register(.init(kind: .feed, column: .feed, posts: { loaded }, canLoadMore: { true }, loadMore: {
      loaded.append(Post(id: "d", subID: "apple"))
      // Another feed showing the same posts, with the same post open.
      _ = targets.register(.init(kind: .feed, column: .feed, posts: { loaded }))
    }))
    let router = router(open: 2, columns: true)
    await targets.openAdjacentPost(1, in: router)?.value
    #expect(router.postColumn.first?.id == feed[2].id)
  }

  @Test func aPageThatArrivesAfterLeavingThePostsTabDoesntOpenAPost() async {
    let targets = CommandTargets()
    var loaded = feed
    _ = targets.register(.init(kind: .feed, column: .feed, posts: { loaded }, canLoadMore: { true }, loadMore: { loaded.append(Post(id: "d", subID: "apple")) }))
    let router = router(open: 2, columns: true)
    await targets.openAdjacentPost(1, in: router, stillShown: { false })?.value
    #expect(router.postColumn.first?.id == feed[2].id)
  }

  @Test func feedsOutsideThePostsTabsFeedColumnArentUsed() {
    let targets = CommandTargets()
    _ = targets.register(.init(kind: .feed, column: .post, posts: { feed }))
    _ = targets.register(.init(kind: .feed, posts: { feed }))
    #expect(targets.adjacentPost(1, in: router(open: 0, columns: true)) == nil)
  }
}

struct ModalTests {
  /// A reply being written, or a full-screen image or video.
  @Test func aModalSuspendsThePostCommands() {
    let targets = CommandTargets()
    _ = targets.register(.init(kind: .post, post: Post(id: "a", subID: "apple")))
    #expect(!targets.showsModal)
    let reply = targets.register(.init(kind: .modal))
    #expect(targets.showsModal)
    // Find and the Post commands are off while it shows.
    #expect(targets.isCovered())
    // A modal isn't a post, refresh or search target.
    #expect(targets.openPost?.post != nil)
    #expect(!targets.canRefresh)
    targets.unregister(reply)
    #expect(!targets.showsModal)
  }
}

struct CommandTargetUpdateTests {
  @Test func anUpdatedTargetChangesWhatTheCommandsCanDo() {
    let targets = CommandTargets()
    let search = targets.register(.init(kind: .search, focusSearch: {}))
    #expect(!targets.canRefresh)
    targets.update(search, to: .init(kind: .search, refresh: {}, focusSearch: {}))
    #expect(targets.canRefresh)
    targets.update(search, to: .init(kind: .search, focusSearch: {}))
    #expect(!targets.canRefresh)
  }
}

struct SubsListSelectionTests {
  private let pics = Router.NavDest.reddit(.subFeed(Subreddit(id: "pics")))
  private let apple = Router.NavDest.reddit(.subFeed(Subreddit(id: "apple")))

  @Test func aFavoritesTwoRowsAreDifferentRowsForTheSameFeed() {
    let favorite = Subreddits.RowSelection(dest: pics, inFavorites: true)
    let regular = Subreddits.RowSelection(dest: pics)
    #expect(favorite != regular)
    #expect(favorite.dest == regular.dest)
  }

  @Test func theRowChosenStaysSelected() {
    let favorite = Subreddits.RowSelection(dest: pics, inFavorites: true)
    #expect(Subreddits.RowSelection.row(for: pics, chosen: favorite) == favorite)
  }

  @Test func aSubredditOpenedByNameSelectsItsCachedRow() throws {
    let json = #"{"name": "t5_2qh1f", "id": "2qh1f", "display_name": "Apple", "url": "/r/Apple/", "public_description": ""}"#
    let cached = try Router.NavDest.reddit(.subFeed(Subreddit(data: JSONDecoder().decode(SubredditData.self, from: Data(json.utf8)))))
    let row = Subreddits.RowSelection(dest: cached)
    #expect(Subreddits.RowSelection.row(for: apple, chosen: nil) == row)
    #expect(Set([row]).contains(.init(dest: apple)))
    #expect(Subreddits.RowSelection(dest: apple, inFavorites: true) != row)
    // Built-in feeds still don't match a subreddit of the same name.
    let rHome = try Router.NavDest.reddit(.subFeed(Subreddit(data: JSONDecoder().decode(SubredditData.self, from: Data(#"{"name": "t5_2qs0q", "id": "2qs0q", "display_name": "home", "url": "/r/home/", "public_description": ""}"#.utf8)))))
    #expect(Subreddits.RowSelection(dest: .reddit(.subFeed(Subreddit(id: "home")))) != .init(dest: rHome))
  }

  @Test func aFavoriteRowThatNoLongerShowsFallsBackToTheRegularRow() {
    let favorite = Subreddits.RowSelection(dest: pics, inFavorites: true)
    #expect(Subreddits.RowSelection.row(for: pics, chosen: favorite, favoriteShows: { _ in false }) == .init(dest: pics))
    #expect(Subreddits.RowSelection.row(for: pics, chosen: favorite, favoriteShows: { _ in true }) == favorite)
  }

  @Test func aFeedOpenedElsewhereSelectsItsRegularRow() {
    let favorite = Subreddits.RowSelection(dest: pics, inFavorites: true)
    #expect(Subreddits.RowSelection.row(for: apple, chosen: favorite) == .init(dest: apple))
    #expect(Subreddits.RowSelection.row(for: pics, chosen: nil) == .init(dest: pics))
    #expect(Subreddits.RowSelection.row(for: nil, chosen: favorite) == nil)
  }
}
