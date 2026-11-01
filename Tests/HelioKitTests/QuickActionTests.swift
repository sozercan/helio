import Testing
import UIKit
@testable import HelioKit

struct QuickActionTests {
  @Test func listsSearchSavedAndTheFirstFavoritesOnce() {
    let list = QuickAction.list(favorites: ["apple", "Apple", " ", "pics", "swift"])
    #expect(list == [.search, .saved, .subreddit("apple"), .subreddit("pics")])
  }

  @Test func listsSearchAndSavedWithoutFavorites() {
    #expect(QuickAction.list(favorites: []) == [.search, .saved])
  }

  @Test func shortcutItemsRoundTrip() {
    for action in [QuickAction.search, .saved, .subreddit("apple")] {
      #expect(QuickAction(action.shortcutItem) == action)
    }
  }

  @Test func subredditItemsCarryTheSubredditName() {
    let item = QuickAction.subreddit("swift").shortcutItem
    #expect(item.userInfo?["name"] as? String == "swift")
    #expect(item.localizedTitle == "r/swift")
  }

  @Test func readsItemsFromOlderVersions() {
    #expect(QuickAction(UIApplicationShortcutItem(type: "Search", localizedTitle: "Search")) == .search)
    #expect(QuickAction(UIApplicationShortcutItem(type: "Saved", localizedTitle: "Saved")) == .saved)
    // Older favorites stored "sub" instead of the subreddit, so they can't be opened.
    #expect(QuickAction(UIApplicationShortcutItem(type: "subFav", localizedTitle: "apple", localizedSubtitle: nil, icon: nil, userInfo: ["name": "sub" as NSString])) == nil)
  }

  @Test func subredditActionOpensTheFeedInPosts() {
    let nav = Nav.shared
    nav[.posts].firstSelected = .reddit(.subFeed(Subreddit(id: "pics")))
    nav[.posts].navigateTo(.reddit(.user(User(id: "someone"))))
    QuickAction.subreddit("apple").perform(on: nav)
    #expect(nav.activeTab == .posts)
    #expect(nav[.posts].fullPath == [.reddit(.subFeed(Subreddit(id: "apple")))])
  }
}
