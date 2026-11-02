//
//  QuickAction.swift
//  Helio
//

import CoreData
import Defaults
import UIKit

/// The app icon's Home Screen quick actions: Search, Saved and the first favorite subreddits.
enum QuickAction: Equatable {
  case search
  case saved
  case subreddit(String)

  /// iOS shows up to four of an app's actions, and Search and Saved take two.
  static let maxSubreddits = 2

  /// Search, Saved, then the first favorites in the order given, each once.
  static func list(favorites: [String]) -> [QuickAction] {
    var seen = Set<String>()
    let subs = favorites
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
      .prefix(maxSubreddits)
      .map(QuickAction.subreddit)
    return [.search, .saved] + subs
  }

  init?(_ item: UIApplicationShortcutItem) {
    switch item.type {
    // Older versions used the capitalized types.
    case "search", "Search": self = .search
    case "saved", "Saved": self = .saved
    case "subreddit":
      guard let name = item.userInfo?["name"] as? String, !name.isEmpty else { return nil }
      self = .subreddit(name)
    default: return nil
    }
  }

  var shortcutItem: UIApplicationShortcutItem {
    switch self {
    case .search:
      UIApplicationShortcutItem(type: "search", localizedTitle: String(localized: "Search"), localizedSubtitle: nil, icon: UIApplicationShortcutIcon(type: .search))
    case .saved:
      UIApplicationShortcutItem(type: "saved", localizedTitle: String(localized: "Saved"), localizedSubtitle: nil, icon: UIApplicationShortcutIcon(type: .bookmark))
    case let .subreddit(name):
      UIApplicationShortcutItem(type: "subreddit", localizedTitle: "r/\(name)", localizedSubtitle: nil, icon: UIApplicationShortcutIcon(type: .love), userInfo: ["name": name as NSString])
    }
  }

  /// Opens the action's tab or feed at its root, closing screens left open on it.
  func perform(on nav: Nav = .shared, subreddit: (String) -> Subreddit = QuickAction.cachedSubreddit(named:)) {
    switch self {
    case .search:
      nav[.search].fullPath = []
      if nav.activeTab != .search {
        nav.activeTab = .search
      }
    case .saved: nav.selectFeed(.reddit(.subFeed(Subreddit(id: savedKeyword))), popToFeed: true)
    case let .subreddit(name): nav.selectFeed(.reddit(.subFeed(subreddit(name))), popToFeed: true)
    }
  }

  /// A default feed by name: the front page, Popular or All, else the subreddit of that name.
  static func subreddit(named name: String) -> Subreddit {
    builtInFeedIDs.contains(name) ? Subreddit(id: name) : cachedSubreddit(named: name)
  }

  /// The current account's cached subreddit with this name, as the sidebar shows it, so the
  /// sidebar marks it selected; a subreddit known only by name otherwise. A favorite named like a
  /// built-in feed (r/home) is still that subreddit.
  static func cachedSubreddit(named name: String) -> Subreddit {
    let context = PersistenceController.shared.container.viewContext
    if let credentialID = Defaults[.GeneralDefSettings].redditCredentialSelectedID {
      let request = CachedSub.fetchRequest()
      request.predicate = NSPredicate(format: "helioCredentialID == %@ AND display_name =[c] %@", credentialID as CVarArg, name)
      request.fetchLimit = 1
      if let cached = try? context.fetch(request).first {
        return Subreddit(data: SubredditData(entity: cached))
      }
    }
    return Subreddit(id: name)
  }

  /// Replaces the app's quick actions with the current account's favorites, as the subs list
  /// shows them.
  static func updateShortcutItems(context: NSManagedObjectContext) {
    var favorites: [String] = []
    if let credentialID = Defaults[.GeneralDefSettings].redditCredentialSelectedID {
      let request = CachedSub.fetchRequest()
      request.predicate = NSPredicate(format: "helioCredentialID == %@ AND user_has_favorited == YES AND user_is_subscriber == YES", credentialID as CVarArg)
      request.sortDescriptors = [NSSortDescriptor(key: "display_name", ascending: true, selector: #selector(NSString.caseInsensitiveCompare(_:)))]
      favorites = ((try? context.fetch(request)) ?? []).compactMap(\.display_name)
    }
    UIApplication.shared.shortcutItems = list(favorites: favorites).map(\.shortcutItem)
  }
}

/// A quick action chosen while the app wasn't running, applied once its scene is active.
var pendingQuickAction: QuickAction?
