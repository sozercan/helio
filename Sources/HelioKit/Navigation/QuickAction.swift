import CoreData
import Defaults
import UIKit

enum QuickAction: Equatable {
  case search
  case saved
  case subreddit(String)

  static let maxSubreddits = 2

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
    case "search", "Search": self = .search
    case "saved", "Saved": self = .saved
    case "subreddit":
      guard let name = item.userInfo?["name"] as? String, !name.isEmpty else { return nil }
      self = .subreddit(name)
    case "subFav":
      let name = item.localizedTitle.hasPrefix("r/") ? String(item.localizedTitle.dropFirst(2)) : item.localizedTitle
      guard !name.isEmpty else { return nil }
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

  func perform(on nav: Nav = .shared, subreddit: (String) -> Subreddit = QuickAction.cachedSubreddit(named:)) {
    switch self {
    case .search:
      nav[.search].fullPath = []
      if nav.activeTab != .search {
        nav.activeTab = .search
      }
      nav.searchFocusRequest += 1
    case .saved: nav.selectFeed(.reddit(.subFeed(Subreddit(id: savedKeyword))), popToFeed: true)
    case let .subreddit(name): nav.selectFeed(.reddit(.subFeed(subreddit(name))), popToFeed: true)
    }
  }

  static func subreddit(named name: String) -> Subreddit {
    builtInFeedIDs.contains(name) ? Subreddit(id: name) : cachedSubreddit(named: name)
  }

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

var pendingQuickAction: QuickAction?
