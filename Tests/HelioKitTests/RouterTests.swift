import Testing
@testable import HelioKit

struct RouterTests {
  private func feed(_ name: String) -> Router.NavDest {
    .reddit(.subFeed(Subreddit(id: name)))
  }

  private let post = Router.NavDest.reddit(.post(Post(id: "abc", subID: "apple")))
  private let user = Router.NavDest.reddit(.user(User(id: "someone")))

  @Test func choosingAnotherFeedReplacesTheWholePath() {
    let router = Router(id: "test")
    router.firstSelected = feed("apple")
    router.navigateTo(post)
    router.navigateTo(user)
    router.firstSelected = feed("pics")
    #expect(router.fullPath == [feed("pics")])
    #expect(router.path.isEmpty)
  }

  @Test func choosingTheSameFeedKeepsItsScreens() {
    let router = Router(id: "test")
    router.firstSelected = feed("apple")
    router.navigateTo(post)
    router.firstSelected = feed("apple")
    #expect(router.fullPath == [feed("apple"), post])
  }

  @Test func clearingTheSelectionEmptiesThePath() {
    let router = Router(id: "test")
    router.firstSelected = feed("apple")
    router.navigateTo(post)
    router.firstSelected = nil
    #expect(router.fullPath.isEmpty)
  }

  @Test func backKeepsTheSidebarSelectionInTheSplitLayout() {
    let router = Router(id: "test")
    router.firstIsSidebarSelection = true
    router.firstSelected = feed("apple")
    router.navigateTo(post)
    #expect(router.canGoBack)
    router.goBack()
    #expect(router.fullPath == [feed("apple")])
    #expect(!router.canGoBack)
    router.goBack()
    #expect(router.fullPath == [feed("apple")])
  }

  @Test func backPopsTheFeedWhenCollapsed() {
    // Compact width: the feed is a pushed screen, and Back returns to the subs list.
    let router = Router(id: "test")
    router.firstSelected = feed("apple")
    #expect(router.canGoBack)
    router.goBack()
    #expect(router.fullPath.isEmpty)
    #expect(!router.canGoBack)
  }

  @Test func backPopsEveryScreenOfAPlainStack() {
    // Inbox, Me, Search and Settings use the whole path as their stack.
    let router = Router(id: "test")
    router.navigateTo(.setting(.appearance))
    router.navigateTo(.setting(.themes))
    router.goBack()
    router.goBack()
    #expect(router.fullPath.isEmpty)
  }
}
