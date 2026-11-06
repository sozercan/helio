import CoreData
import Foundation
import SwiftUI
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

  @Test func aFeedKeepsItsSettingsKeyWhicheverDetailsItHolds() throws {
    // The sidebar's copy comes from the cache, which keys a subreddit by its fullname; Reddit's
    // own details carry the bare id; a link knows only the name.
    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: AccountListSyncAuthorizationTests.model)
    try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
    let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    context.persistentStoreCoordinator = coordinator
    let json = #"{"name": "t5_2qh1f", "id": "2qh1f", "display_name": "Apple", "url": "/r/Apple/", "public_description": "", "user_has_favorited": true}"#
    let full = try JSONDecoder().decode(SubredditData.self, from: Data(json.utf8))
    let cached = context.performAndWait { SubredditData(entity: CachedSub(data: full, context: context, credentialID: UUID())) }
    #expect(cached.id != full.id)
    #expect(Subreddit(data: cached).settingsKey == "t5_2qh1f")
    #expect(Subreddit(data: full).settingsKey == "t5_2qh1f")
    #expect(Subreddit(id: "apple").settingsKey == "apple")

    // Reselected from the sidebar, then Reddit's details landing late: the key stays.
    let feed = Subreddit(data: full)
    let router = Router(id: "test")
    router.firstSelected = .reddit(.subFeed(feed))
    router.firstSelected = .reddit(.subFeed(Subreddit(data: cached)))
    #expect(feed.settingsKey == "t5_2qh1f")
    feed.data = full
    #expect(feed.settingsKey == "t5_2qh1f")
  }

  @Test func aSettingSavedUnderAnOlderKeyKeepsApplying() {
    func key(_ saved: [String: Bool]) -> String {
      Subreddit.settingsKey(fullname: "t5_2qh1f", bareID: "2qh1f", name: "Apple", id: "2qh1f", saved: saved)
    }
    // Nothing saved yet: the fullname.
    #expect(key([:]) == "t5_2qh1f")
    // Saved from a feed with Reddit's own details, or one opened by name, before.
    #expect(key(["2qh1f": true]) == "2qh1f")
    #expect(key(["Apple": true]) == "Apple")
    #expect(key(["apple": true]) == "apple")
    // The fullname wins once it's there.
    #expect(key(["t5_2qh1f": false, "2qh1f": true]) == "t5_2qh1f")
    // Known only by name.
    #expect(Subreddit.settingsKey(fullname: nil, bareID: nil, name: nil, id: "apple", saved: [:]) == "apple")
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

  // MARK: The posts split view's feed and post columns

  private let otherPost = Router.NavDest.reddit(.post(Post(id: "def", subID: "apple")))
  private let sub = Router.NavDest.reddit(.subFeed(Subreddit(id: "pics")))

  @Test func aPostFromTheFeedOpensInThePostColumn() {
    let router = Router(id: "test")
    router.firstSelected = feed("apple")
    router.navigateTo(post, from: .feed)
    #expect(router.feedPath.isEmpty)
    #expect(router.postColumn == [post])
    #expect(router.postPath.isEmpty)
  }

  @Test func anotherPostFromTheFeedReplacesThePostColumn() {
    let router = Router(id: "test")
    router.firstSelected = feed("apple")
    router.navigateTo(post, from: .feed)
    router.navigateTo(user, from: .post)
    router.navigateTo(otherPost, from: .feed)
    #expect(router.fullPath == [feed("apple"), otherPost])
  }

  @Test func screensOpenedFromThePostStackInThePostColumn() {
    let router = Router(id: "test")
    router.firstSelected = feed("apple")
    router.navigateTo(post, from: .feed)
    router.navigateTo(user, from: .post)
    router.navigateTo(otherPost, from: .post)
    #expect(router.feedPath.isEmpty)
    #expect(router.postColumn == [post, user, otherPost])
    #expect(router.postPath == [user, otherPost])
  }

  @Test func aWebPageFromTheFeedOpensInThePostColumnAndOneFromThePostStacksOnIt() throws {
    let page = try Router.NavDest.web(#require(URL(string: "https://example.com/article")))
    let router = Router(id: "test")
    router.firstSelected = feed("apple")
    router.navigateTo(post, from: .feed)
    router.navigateTo(page, from: .feed)
    #expect(router.fullPath == [feed("apple"), page])
    #expect(router.postColumn == [page])

    router.navigateTo(post, from: .feed)
    router.navigateTo(page, from: .post)
    #expect(router.postColumn == [post, page])
    #expect(router.postPath == [page])
  }

  @Test func aSubredditFromTheFeedStacksOnTheFeedAndKeepsTheOpenPost() {
    let router = Router(id: "test")
    router.firstSelected = feed("apple")
    router.navigateTo(post, from: .feed)
    router.navigateTo(sub, from: .feed)
    #expect(router.feedPath == [sub])
    #expect(router.postColumn == [post])
    // Collapsed into one stack, the order is the same.
    #expect(router.fullPath == [feed("apple"), sub, post])
  }

  @Test func poppingTheFeedColumnKeepsTheOpenPost() {
    let router = Router(id: "test")
    router.firstSelected = feed("apple")
    router.navigateTo(sub, from: .feed)
    router.navigateTo(post, from: .feed)
    router.feedPath = []
    #expect(router.fullPath == [feed("apple"), post])
  }

  @Test func poppingThePostColumnKeepsItsRoot() {
    let router = Router(id: "test")
    router.firstSelected = feed("apple")
    router.navigateTo(post, from: .feed)
    router.navigateTo(user, from: .post)
    router.postPath = []
    #expect(router.fullPath == [feed("apple"), post])
  }

  @Test func closingThePostEmptiesThePostColumnOnly() {
    let router = Router(id: "test")
    router.firstSelected = feed("apple")
    router.navigateTo(sub, from: .feed)
    router.navigateTo(post, from: .feed)
    router.navigateTo(user, from: .post)
    router.closePost()
    #expect(router.fullPath == [feed("apple"), sub])
    #expect(router.postColumnStart == nil)
  }

  @Test func backInTheSplitLayoutClosesThePostThenPopsTheFeedButKeepsIt() {
    let router = Router(id: "test")
    router.firstIsSidebarSelection = true
    router.firstSelected = feed("apple")
    router.navigateTo(sub, from: .feed)
    router.navigateTo(post, from: .feed)
    router.goBack()
    #expect(router.fullPath == [feed("apple"), sub])
    router.goBack()
    #expect(router.fullPath == [feed("apple")])
    router.goBack()
    #expect(router.fullPath == [feed("apple")])
  }

  @Test func choosingAnotherFeedClosesTheOpenPost() {
    let router = Router(id: "test")
    router.firstSelected = feed("apple")
    router.navigateTo(post, from: .feed)
    router.firstSelected = feed("pics")
    #expect(router.postColumn.isEmpty)
  }

  @Test func aPostChosenAsTheFeedIsNotThePostColumn() {
    // A post can be the sidebar's selection itself (a link opened from another tab).
    let router = Router(id: "test")
    router.firstSelected = post
    #expect(router.postColumnStart == nil)
    router.navigateTo(otherPost, from: .feed)
    #expect(router.postColumn == [otherPost])
  }

  // MARK: The open Duo's panes

  @Test func theFeedPaneHoldsTheFeedAndItsScreensButNotThePost() {
    let router = Router(id: "test")
    router.firstSelected = feed("apple")
    router.navigateTo(sub, from: .feed)
    router.navigateTo(post, from: .feed)
    #expect(router.feedPanePath == [feed("apple"), sub])
    // Popping a screen stacked on the feed keeps the open post.
    router.feedPanePath = [feed("apple")]
    #expect(router.fullPath == [feed("apple"), post])
  }

  @Test func goingBackToTheSubsListInTheFeedPaneClosesThePost() {
    let router = Router(id: "test")
    router.firstSelected = feed("apple")
    router.navigateTo(post, from: .feed)
    router.feedPanePath = []
    #expect(router.fullPath.isEmpty)
  }

  @Test func backInTheDuoPanesClosesThePostThenTheFeed() {
    // The feed is pushed on the subs list there, so Back can leave it.
    let router = Router(id: "test")
    router.showsPostBesideFeed = true
    router.firstSelected = feed("apple")
    router.navigateTo(post, from: .feed)
    router.goBack()
    #expect(router.fullPath == [feed("apple")])
    #expect(router.canGoBack)
    router.goBack()
    #expect(router.fullPath.isEmpty)
  }

  @Test func feedPathIgnoresPushesWithoutAFeed() {
    let router = Router(id: "test")
    router.feedPath = [sub]
    #expect(router.fullPath.isEmpty)
  }
}

struct SplitLayoutTests {
  private func frame(_ width: CGFloat) -> CGRect {
    CGRect(x: 0, y: 0, width: width, height: 900)
  }

  @Test func compactWidthIsOneStack() {
    #expect(!SplitLayout(sizeClass: .compact, frame: frame(1000), division: nil).showsColumns)
  }

  @Test func aNarrowRegularWindowIsOneStack() {
    let layout = SplitLayout(sizeClass: .regular, frame: frame(SplitLayout.minFeedWidth + SplitLayout.minPostWidth - 1), division: nil)
    #expect(!layout.showsColumns)
    #expect(!layout.fitsSidebar)
  }

  @Test func aWideWindowShowsTheFeedAndThePost() {
    let layout = SplitLayout(sizeClass: .regular, frame: frame(820), division: nil)
    #expect(layout.showsColumns)
    #expect(!layout.fitsSidebar)
    #expect(layout.hingeFeedWidth == nil)
  }

  @Test func aFullScreenIPadShowsTheSidebarToo() {
    #expect(SplitLayout(sizeClass: .regular, frame: frame(1366), division: nil).fitsSidebar)
  }

  @Test func theOpenDuoSplitsAtItsHinge() {
    let hinge = CGRect(x: 330, y: 0, width: 8, height: 900)
    for sizeClass in [UserInterfaceSizeClass.compact, .regular] {
      let layout = SplitLayout(sizeClass: sizeClass, frame: frame(668), division: hinge)
      #expect(layout.showsColumns)
      #expect(layout.hingeFeedWidth == 330)
      #expect(layout.hingeWidth == 8)
      // A hinge nearer than a feed column's width: the panes meet in its middle.
      #expect(layout.feedPaneWidth == 334)
    }
  }

  @Test func theOpenDuoKeepsTheFeedPaneToAFeedColumnsWidth() {
    // The Duo's measured inner screen: the hinge's middle is 475 pt in, the post pane gets the rest.
    let layout = SplitLayout(sizeClass: .regular, frame: frame(867), division: CGRect(x: 455.5, y: 0, width: 40, height: 669))
    #expect(layout.feedPaneWidth == SplitLayout.idealFeedWidth)
  }

  @Test func theOpenDuoUsesTwoPanesInsteadOfTheSplitView() {
    // Each half is narrower than the split view tiles a feed and a post, so it would overlay them.
    let layout = SplitLayout(sizeClass: .regular, frame: frame(668), division: CGRect(x: 330, y: 0, width: 8, height: 900))
    #expect(layout.usesPanes)
    #expect(!layout.fitsSidebar)
    // The subs list is the feed pane's first screen, not a sidebar beside the feed.
    #expect(!layout.sidebarBesideFeed)
  }

  @Test func wideWindowsKeepTheSplitView() {
    for width in [820.0, 1366] {
      let layout = SplitLayout(sizeClass: .regular, frame: frame(width), division: nil)
      #expect(!layout.usesPanes)
      #expect(layout.sidebarBesideFeed)
    }
    #expect(!SplitLayout(sizeClass: .compact, frame: frame(390), division: nil).usesPanes)
    #expect(!SplitLayout(sizeClass: .regular, frame: frame(668), division: CGRect(x: 0, y: 440, width: 668, height: 8)).usesPanes)
  }

  @Test func aHorizontalHingeDoesNotSizeTheFeed() {
    let hinge = CGRect(x: 0, y: 440, width: 668, height: 8)
    let layout = SplitLayout(sizeClass: .regular, frame: frame(668), division: hinge)
    #expect(layout.hingeFeedWidth == nil)
    // It doesn't separate a left and a right column, so the width rule still collapses them.
    #expect(!layout.showsColumns)
  }

  @Test func beforeMeasuringTheSizeClassDecides() {
    #expect(SplitLayout(sizeClass: .regular, frame: .zero, division: nil).showsColumns)
    #expect(!SplitLayout(sizeClass: .compact, frame: .zero, division: nil).showsColumns)
    // The launch feed waits for a measurement: a narrow regular window is one stack.
    #expect(!SplitLayout(sizeClass: .regular, frame: .zero, division: nil).measured)
    #expect(SplitLayout(sizeClass: .regular, frame: frame(700), division: nil).measured)
  }
}

struct ReadableWidthTests {
  private func column(_ x: CGFloat, _ width: CGFloat) -> CGRect {
    CGRect(x: x, y: 0, width: width, height: 900)
  }

  @Test func wideColumnsAreCapped() {
    #expect(ReadableWidth.contentWidth(column: column(0, 1200), visibleWidth: 1200, division: nil) == ReadableWidth.max)
    #expect(ReadableWidth.contentWidth(column: column(0, 500), visibleWidth: 500, division: nil) == 500)
  }

  @Test func aColumnAcrossTheOpenDuosHingeUsesItsWholeWidth() {
    let hinge = CGRect(x: 580, y: 0, width: 40, height: 900)
    #expect(ReadableWidth.contentWidth(column: column(0, 1200), visibleWidth: 1200, division: hinge) == 1200)
  }

  @Test func theOpenDuosPanesGetTheirOwnWidth() {
    // The open Duo flat on its back: the side tab bar takes the window's right 84 pt, and the
    // hinge is 40 pt wide in the middle of the window.
    let hinge = CGRect(x: 455.5, y: 0, width: 40, height: 669)
    let feedPane = column(0, 455.5)
    let postPane = CGRect(x: 495.5, y: 0, width: 455.5, height: 669)
    #expect(ReadableWidth.contentWidth(column: feedPane, visibleWidth: 455.5, division: hinge) == 455.5)
    // The post pane runs under the tab bar; its content stops at the window's safe area.
    #expect(ReadableWidth.contentWidth(column: postPane, visibleWidth: 371.5, division: hinge) == 371.5)
    // A pane on one side of the hinge is capped like any column.
    let farHinge = CGRect(x: 1000, y: 0, width: 40, height: 900)
    #expect(ReadableWidth.contentWidth(column: column(0, 1000), visibleWidth: 1000, division: farHinge) == ReadableWidth.max)
  }
}

struct RedditLinkTests {
  @Test func webLinksBecomeAppLinks() throws {
    for host in ["reddit.com", "www.reddit.com", "old.reddit.com"] {
      let url = try #require(URL(string: "https://\(host)/r/apple/comments/abc123/a_title/"))
      #expect(parseRedditURL(Nav.appLink(for: url)) == .post(id: "abc123", subreddit: "apple"))
    }
    let other = try #require(URL(string: "https://example.com/r/apple"))
    #expect(Nav.appLink(for: other) == other.absoluteString)
  }

  @Test func commentLinksOpenTheirPostAndWikiLinksDont() throws {
    let comment = try #require(URL(string: "https://old.reddit.com/r/apple/comments/abc123/a_title/def456/"))
    guard case let .reddit(.postHighlighted(post, highlight)) = Nav.linkDestination(for: comment) else {
      Issue.record("expected the comment in its post")
      return
    }
    #expect(post.id == "abc123")
    #expect(highlight == "def456")
    let wiki = try #require(URL(string: "https://www.reddit.com/r/apple/wiki/index"))
    #expect(Nav.linkDestination(for: wiki) == nil)
    // A subreddit's comments listing has no post id: opened as the page, not a crash.
    let listing = try #require(URL(string: "https://www.reddit.com/r/apple/comments/"))
    #expect(Nav.linkDestination(for: listing) == nil)
  }
}

struct LaunchFeedTests {
  private let home = Router.NavDest.reddit(.subFeed(Subreddit(id: "home")))

  @Test func wideLayoutsOpenHomeInsteadOfAnEmptyFeedColumn() {
    #expect(SubredditsStack.launchFeed(defaultFeed: "subList", showsColumns: true, current: nil) == home)
  }

  @Test func aStackStillOpensOnTheSubsList() {
    #expect(SubredditsStack.launchFeed(defaultFeed: "subList", showsColumns: false, current: nil) == nil)
  }

  @Test func theDefaultLaunchFeedWinsOverHome() {
    let popular = Router.NavDest.reddit(.subFeed(Subreddit(id: "popular")))
    #expect(SubredditsStack.launchFeed(defaultFeed: "popular", showsColumns: true, current: nil) == popular)
    #expect(SubredditsStack.launchFeed(defaultFeed: "popular", showsColumns: false, current: nil) == popular)
  }

  @Test func aFeedAlreadyChosenStays() {
    let chosen = Router.NavDest.reddit(.subFeed(Subreddit(id: "pics")))
    #expect(SubredditsStack.launchFeed(defaultFeed: "subList", showsColumns: true, current: chosen) == nil)
    #expect(SubredditsStack.launchFeed(defaultFeed: "popular", showsColumns: false, current: chosen) == nil)
  }
}
