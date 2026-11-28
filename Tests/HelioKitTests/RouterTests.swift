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
    router.firstSelected = feed("apple")
    #expect(router.fullPath == [cached, post])
  }

  @Test func aFeedOpenedByNameTakesTheDetailsInPlace() throws {
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
    #expect(router.firstSelected == .reddit(.subFeed(cached)))
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
    #expect(key([:]) == "t5_2qh1f")
    #expect(key(["2qh1f": true]) == "2qh1f")
    #expect(key(["Apple": true]) == "Apple")
    #expect(key(["apple": true]) == "apple")
    #expect(key(["t5_2qh1f": false, "2qh1f": true]) == "t5_2qh1f")
    #expect(Subreddit.settingsKey(fullname: nil, bareID: nil, name: nil, id: "apple", saved: [:]) == "apple")
  }

  @Test func reselectingAFeedKeepsDetailsTheSidebarsCopyLacks() throws {
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
    let router = Router(id: "test")
    router.firstSelected = feed("apple")
    #expect(router.canGoBack)
    router.goBack()
    #expect(router.fullPath.isEmpty)
    #expect(!router.canGoBack)
  }

  @Test func backPopsEveryScreenOfAPlainStack() {
    let router = Router(id: "test")
    router.navigateTo(.setting(.appearance))
    router.navigateTo(.setting(.themes))
    router.goBack()
    router.goBack()
    #expect(router.fullPath.isEmpty)
  }

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
    router.showsPostBesideFeed = true
    router.firstSelected = feed("apple")
    router.navigateTo(post, from: .feed)
    router.navigateTo(user, from: .post)
    router.navigateTo(otherPost, from: .feed)
    #expect(router.fullPath == [feed("apple"), otherPost])
  }

  @Test func screensOpenedFromThePostStackInThePostColumn() {
    let router = Router(id: "test")
    router.showsPostBesideFeed = true
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
    router.showsPostBesideFeed = true
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
    router.showsPostBesideFeed = true
    router.firstSelected = feed("apple")
    router.navigateTo(post, from: .feed)
    router.navigateTo(sub, from: .feed)
    #expect(router.feedPath == [sub])
    #expect(router.postColumn == [post])
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
    let router = Router(id: "test")
    router.firstSelected = post
    #expect(router.postColumnStart == nil)
    router.navigateTo(otherPost, from: .feed)
    #expect(router.postColumn == [otherPost])
  }

  @Test func theFeedPaneHoldsTheFeedAndItsScreensButNotThePost() {
    let router = Router(id: "test")
    router.firstSelected = feed("apple")
    router.navigateTo(sub, from: .feed)
    router.navigateTo(post, from: .feed)
    #expect(router.feedPanePath == [feed("apple"), sub])
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

  @Test func compactStackPushesPostOpenedFromPostOnTopInsteadOfReplacing() {
    let router = Router(id: "test")
    router.showsPostBesideFeed = false
    router.firstSelected = feed("apple")
    router.navigateTo(post, from: .feed)
    router.navigateTo(otherPost, from: .feed)
    #expect(router.fullPath == [feed("apple"), post, otherPost])
    router.goBack()
    #expect(router.fullPath == [feed("apple"), post])
    router.goBack()
    #expect(router.fullPath == [feed("apple")])
  }

  @Test func compactStackPushesSubredditAndWebPageOnTopOfPost() throws {
    let page = try Router.NavDest.web(#require(URL(string: "https://example.com/article")))
    let router = Router(id: "test")
    router.showsPostBesideFeed = false
    router.firstSelected = feed("apple")
    router.navigateTo(post, from: .feed)
    router.navigateTo(page, from: .feed)
    #expect(router.fullPath == [feed("apple"), post, page])
    #expect(router.compactPath.map(\.column) == [.feed, .post, .post])
    router.goBack()
    #expect(router.fullPath == [feed("apple"), post])

    router.navigateTo(sub, from: .feed)
    #expect(router.fullPath == [feed("apple"), post, sub])
    #expect(router.compactPath.map(\.column) == [.feed, .post, .post])
    router.goBack()
    #expect(router.fullPath == [feed("apple"), post])
  }

  @Test func compactPathClassifiesEqualFeedsByPositionAcrossPostBoundary() {
    let router = Router(id: "test")
    router.showsPostBesideFeed = false
    let apple = feed("apple")
    router.firstSelected = apple
    router.navigateTo(post, from: .feed)
    router.navigateTo(apple, from: .post)

    #expect(router.compactPath == [
      Router.CompactPathEntry(dest: apple, column: .feed),
      Router.CompactPathEntry(dest: post, column: .post),
      Router.CompactPathEntry(dest: apple, column: .post),
    ])

    router.compactPath.removeLast()
    #expect(router.fullPath == [apple, post])
  }

  @Test @MainActor func contentPopGestureTracksEveryAttachedNavigationControllerIndependently() {
    let holder = ViewControllerHolder(routerID: "posts")
    let feedRoot = UIViewController()
    let feedNav = UINavigationController(rootViewController: feedRoot)
    let postRoot = UIViewController()
    let postNav = UINavigationController(rootViewController: postRoot)

    holder.attach(feedRoot)
    holder.attach(postRoot)
    holder.setSwipeAnywhereEnabled(true)

    #expect(feedNav.interactiveContentPopGestureRecognizer?.isEnabled == true)
    #expect(postNav.interactiveContentPopGestureRecognizer?.isEnabled == true)

    holder.setSwipeAnywhereEnabled(false)
    #expect(feedNav.interactiveContentPopGestureRecognizer?.isEnabled == false)
    #expect(postNav.interactiveContentPopGestureRecognizer?.isEnabled == false)
  }

  @Test @MainActor func attachWalksUpToEnclosingNavigationControllers() {
    let holder = ViewControllerHolder(routerID: "posts")
    let leaf = UIViewController()
    let container = UIViewController()
    container.addChild(leaf)
    let nav = UINavigationController(rootViewController: container)

    holder.setSwipeAnywhereEnabled(true)
    holder.attach(leaf)
    #expect(nav.interactiveContentPopGestureRecognizer?.isEnabled == true)
  }

  @Test func swipeActionsSetReportsActiveDirections() {
    let none = AnySwipeAction(NoneAction())
    let upvote = AnySwipeAction(UpvotePostAction())

    let allNone = SwipeActionsSet(id: "none", leftFirst: none, leftSecond: none, rightFirst: none, rightSecond: none)
    #expect(!allNone.hasLeftActions)
    #expect(!allNone.hasRightActions)
    #expect(!allNone.hasAnyActions)
    #expect(SwipeUI<PostData, PostHelioData>.clampedDragOffset(translationWidth: 80, initialOffset: 30, actionsSet: allNone) == 0)
    #expect(SwipeUI<PostData, PostHelioData>.clampedDragOffset(translationWidth: -80, initialOffset: -30, actionsSet: allNone) == 0)

    let leftOnly = SwipeActionsSet(id: "left", leftFirst: upvote, leftSecond: none, rightFirst: none, rightSecond: none)
    #expect(leftOnly.hasLeftActions)
    #expect(!leftOnly.hasRightActions)
    #expect(leftOnly.hasAnyActions)
    #expect(SwipeUI<PostData, PostHelioData>.clampedDragOffset(translationWidth: 80, initialOffset: 30, actionsSet: leftOnly) == 0)
    #expect(SwipeUI<PostData, PostHelioData>.clampedDragOffset(translationWidth: -80, initialOffset: -30, actionsSet: leftOnly) == -50)

    let rightOnly = SwipeActionsSet(id: "right", leftFirst: none, leftSecond: none, rightFirst: upvote, rightSecond: none)
    #expect(!rightOnly.hasLeftActions)
    #expect(rightOnly.hasRightActions)
    #expect(rightOnly.hasAnyActions)
    #expect(SwipeUI<PostData, PostHelioData>.clampedDragOffset(translationWidth: 80, initialOffset: 30, actionsSet: rightOnly) == 50)
    #expect(SwipeUI<PostData, PostHelioData>.clampedDragOffset(translationWidth: -80, initialOffset: -30, actionsSet: rightOnly) == 0)
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
      #expect(layout.feedPaneWidth == 334)
    }
  }

  @Test func theOpenDuoKeepsTheFeedPaneToAFeedColumnsWidth() {
    let layout = SplitLayout(sizeClass: .regular, frame: frame(867), division: CGRect(x: 455.5, y: 0, width: 40, height: 669))
    #expect(layout.feedPaneWidth == SplitLayout.idealFeedWidth)
  }

  @Test func theOpenDuoUsesTwoPanesInsteadOfTheSplitView() {
    let layout = SplitLayout(sizeClass: .regular, frame: frame(668), division: CGRect(x: 330, y: 0, width: 8, height: 900))
    #expect(layout.usesPanes)
    #expect(!layout.fitsSidebar)
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
    #expect(!layout.showsColumns)
  }

  @Test func beforeMeasuringTheSizeClassDecides() {
    #expect(SplitLayout(sizeClass: .regular, frame: .zero, division: nil).showsColumns)
    #expect(!SplitLayout(sizeClass: .compact, frame: .zero, division: nil).showsColumns)
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
    let hinge = CGRect(x: 455.5, y: 0, width: 40, height: 669)
    let feedPane = column(0, 455.5)
    let postPane = CGRect(x: 495.5, y: 0, width: 455.5, height: 669)
    #expect(ReadableWidth.contentWidth(column: feedPane, visibleWidth: 455.5, division: hinge) == 455.5)
    #expect(ReadableWidth.contentWidth(column: postPane, visibleWidth: 371.5, division: hinge) == 371.5)
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
