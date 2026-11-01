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

  /// Opens the action's tab or feed.
  func perform(on nav: Nav = .shared) {
    switch self {
    case .search: nav.activeTab = .search
    case .saved: nav.selectFeed(.reddit(.subFeed(Subreddit(id: savedKeyword))))
    case let .subreddit(name): nav.selectFeed(.reddit(.subFeed(Subreddit(id: name))))
    }
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
