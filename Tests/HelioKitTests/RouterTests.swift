import Foundation
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

  @Test func aSubredditKnownByNameIsTheSameFeedAsItsCachedCopy() throws {
    // The sidebar's cached subreddit has Reddit's id; a quick action knows only the name.
    let json = #"{"name": "t5_2qh1f", "id": "2qh1f", "display_name": "Apple", "url": "/r/Apple/", "public_description": ""}"#
    let cached = try Subreddit(data: JSONDecoder().decode(SubredditData.self, from: Data(json.utf8)))
    let router = Router(id: "test")
    router.firstSelected = .reddit(.subFeed(cached))
    router.navigateTo(post)
    router.firstSelected = feed("apple")
    #expect(router.fullPath.count == 2)
    #expect(feed("apple").isSameFeed(as: .reddit(.subFeed(cached))))
    #expect(!feed("pics").isSameFeed(as: .reddit(.subFeed(cached))))
  }

  @Test func builtInFeedsDontMatchSubredditsOfTheSameName() throws {
    let json = #"{"name": "t5_2qs0q", "id": "2qs0q", "display_name": "home", "url": "/r/home/", "public_description": ""}"#
    let rHome = try Subreddit(data: JSONDecoder().decode(SubredditData.self, from: Data(json.utf8)))
    #expect(!feed("home").isSameFeed(as: .reddit(.subFeed(rHome))))
    #expect(QuickAction.subreddit(named: "home").data == nil)
  }

  @Test func theSameFeedTakesTheSubredditsDetails() throws {
    let json = #"{"name": "t5_2qh1f", "id": "2qh1f", "display_name": "Apple", "url": "/r/Apple/", "public_description": ""}"#
    let cached = try Router.NavDest.reddit(.subFeed(Subreddit(data: JSONDecoder().decode(SubredditData.self, from: Data(json.utf8)))))
    let router = Router(id: "test")
    router.firstSelected = feed("apple")
    router.navigateTo(post)
    router.firstSelected = cached
    #expect(router.fullPath == [cached, post])
    // Choosing the name-only feed again doesn't drop the details.
    router.firstSelected = feed("apple")
    #expect(router.fullPath == [cached, post])
  }

  @Test func aFeedOpenedByNameTakesTheDetailsInPlace() throws {
    // Its feed view and loaded posts hold this subreddit; replacing it would split them from the
    // per-subreddit settings, which are kept by Reddit's id.
    let json = #"{"name": "t5_2qh1f", "id": "2qh1f", "display_name": "Apple", "url": "/r/Apple/", "public_description": ""}"#
    let cached = try Subreddit(data: JSONDecoder().decode(SubredditData.self, from: Data(json.utf8)))
    let byName = Subreddit(id: "apple")
    let router = Router(id: "test")
    router.firstSelected = .reddit(.subFeed(byName))
    let nameBefore = router.fullPath.first?.subredditFeedName
    router.firstSelected = .reddit(.subFeed(cached))
    guard case let .reddit(.subFeed(sub)) = router.fullPath.first else {
      Issue.record("expected a subreddit feed")
      return
    }
    #expect(sub === byName)
    #expect(sub.id == cached.id)
    // The sidebar's selection matches the cached row.
    #expect(router.firstSelected == .reddit(.subFeed(cached)))
    // The feed view is keyed by this, so it isn't rebuilt.
    #expect(router.fullPath.first?.subredditFeedName == nameBefore)
  }

  @Test func showingAFeedRootByNameKeepsItsSubreddit() throws {
    let json = #"{"name": "t5_2qh1f", "id": "2qh1f", "display_name": "Apple", "url": "/r/Apple/", "public_description": ""}"#
    let cached = try Subreddit(data: JSONDecoder().decode(SubredditData.self, from: Data(json.utf8)))
    let byName = Subreddit(id: "apple")
    let router = Router(id: "test")
    router.firstSelected = .reddit(.subFeed(byName))
    router.navigateTo(post)
    router.showFeedRoot(.reddit(.subFeed(cached)))
    #expect(router.fullPath.count == 1)
    guard case let .reddit(.subFeed(sub)) = router.fullPath.first else {
      Issue.record("expected a subreddit feed")
      return
    }
    #expect(sub === byName)
    #expect(sub.data?.display_name == "Apple")
  }

  @Test func reselectingAFeedKeepsDetailsTheSidebarsCopyLacks() throws {
    // The feed's subreddit has Reddit's full response; the sidebar's copy fills what it doesn't
    // keep with placeholders (no description, a public type).
    let full = #"{"name": "t5_2qh1f", "id": "2qh1f", "display_name": "Apple", "url": "/r/Apple/", "public_description": "Apple news", "description": "All things Apple", "subreddit_type": "restricted", "user_has_favorited": false}"#
    let partial = #"{"name": "t5_2qh1f", "id": "2qh1f", "display_name": "Apple", "url": "/r/Apple/", "public_description": "", "subreddit_type": "public", "user_has_favorited": true}"#
    let feed = try Subreddit(data: JSONDecoder().decode(SubredditData.self, from: Data(full.utf8)))
    let sidebar = try Subreddit(data: JSONDecoder().decode(SubredditData.self, from: Data(partial.utf8)))
    let router = Router(id: "test")
    router.firstSelected = .reddit(.subFeed(feed))
    router.navigateTo(post)
    router.firstSelected = .reddit(.subFeed(sidebar))
    #expect(feed.data?.description == "All things Apple")
    #expect(feed.data?.public_description == "Apple news")
    #expect(feed.data?.subreddit_type == "restricted")
    // The account's state is the sidebar's, the fresher.
    #expect(feed.data?.user_has_favorited == true)
    #expect(router.fullPath.count == 2)
  }

  @Test func backClosesAPostOpenedFirstBesideTheSidebar() {
    let router = Router(id: "test")
    router.firstIsSidebarSelection = true
    router.firstSelected = post
    #expect(router.canGoBack)
    router.goBack()
    #expect(router.fullPath.isEmpty)
  }

  @Test func showingTheFeedRootClosesItsScreens() {
    let router = Router(id: "test")
    router.firstSelected = feed("apple")
    router.navigateTo(post)
    router.showFeedRoot(feed("apple"))
    #expect(router.fullPath == [feed("apple")])
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
