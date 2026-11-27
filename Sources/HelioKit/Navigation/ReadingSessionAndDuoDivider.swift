import CoreData
import Defaults
import Foundation

struct ReadingSessionSnapshot: Equatable, Codable, Sendable {
  let accountID: UUID
  let feedName: String
  let savedAt: Date
}

enum ReadingSessionStore {
  private static let storageKey = "Helio.ReadingSessionSnapshots.v1"
  private static let builtInPrefix = "feed:"
  private static let multiPrefix = "multi:"

  static func save(
    feedName: String,
    accountID: UUID,
    defaults: UserDefaults = .standard,
    now: Date = Date(),
  ) {
    let normalized = feedName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return }
    var snapshots = loadAll(defaults: defaults)
    snapshots[accountID.uuidString] = ReadingSessionSnapshot(accountID: accountID, feedName: normalized, savedAt: now)
    if let data = try? JSONEncoder().encode(snapshots) {
      defaults.set(data, forKey: storageKey)
    }
  }

  static func load(accountID: UUID?, defaults: UserDefaults = .standard) -> ReadingSessionSnapshot? {
    guard let accountID else { return nil }
    return loadAll(defaults: defaults)[accountID.uuidString]
  }

  static func clearAll(defaults: UserDefaults = .standard) {
    defaults.removeObject(forKey: storageKey)
  }

  static func feedIdentifier(for dest: Router.NavDest) -> String? {
    switch dest {
    case .reddit(.subFeed):
      return dest.subredditFeedName
    case let .reddit(.multiFeed(multi)):
      let path = (multi.data?.path ?? multi.id).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !path.isEmpty else { return nil }
      return "\(multiPrefix)\(path)"
    default:
      return nil
    }
  }

  static func latestFeedName(in path: [Router.NavDest]) -> String? {
    path.last(where: { feedIdentifier(for: $0) != nil }).flatMap(feedIdentifier(for:))
  }

  static func saveCurrentFeed(
    in path: [Router.NavDest],
    accountID: UUID?,
    defaults: UserDefaults = .standard,
    now: Date = Date(),
  ) {
    guard let accountID, let feedName = latestFeedName(in: path) else { return }
    save(feedName: feedName, accountID: accountID, defaults: defaults, now: now)
  }

  static func destination(
    forSavedFeedName savedName: String,
    accountID: UUID? = Defaults[.GeneralDefSettings].redditCredentialSelectedID,
    resolveSubreddit: (String) -> Subreddit = { resolveOrdinarySubreddit(named: $0) },
    resolveMulti: (String, UUID?) -> Multi? = { cachedMulti(path: $0, accountID: $1) },
  ) -> Router.NavDest? {
    let trimmed = savedName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.hasPrefix(builtInPrefix) {
      let builtInID = String(trimmed.dropFirst(builtInPrefix.count))
      guard !builtInID.isEmpty else { return nil }
      return .reddit(.subFeed(Subreddit(id: builtInID)))
    }
    if trimmed.hasPrefix(multiPrefix) {
      let multiPath = String(trimmed.dropFirst(multiPrefix.count))
      guard !multiPath.isEmpty, let multi = resolveMulti(multiPath, accountID) else { return nil }
      return .reddit(.multiFeed(multi))
    }
    return .reddit(.subFeed(resolveSubreddit(trimmed)))
  }

  static func resolveOrdinarySubreddit(
    named name: String,
    lookupCached: (String) -> Subreddit = QuickAction.cachedSubreddit(named:),
  ) -> Subreddit {
    let sub = lookupCached(name)
    if sub.data == nil, builtInFeedIDs.contains(sub.id) {
      return Subreddit(id: "/r/\(name)/")
    }
    return sub
  }

  static func cachedMulti(
    path: String,
    accountID: UUID?,
    context: NSManagedObjectContext = PersistenceController.shared.container.viewContext,
  ) -> Multi? {
    guard let accountID else { return nil }
    let request = CachedMulti.fetchRequest()
    request.predicate = NSPredicate(format: "helioCredentialID == %@ AND path =[c] %@", accountID as CVarArg, path)
    request.fetchLimit = 1
    guard let cached = context.performAndWait({ try? context.fetch(request).first }) else { return nil }
    return Multi(data: MultiData(entity: cached))
  }

  private static func loadAll(defaults: UserDefaults) -> [String: ReadingSessionSnapshot] {
    guard
      let data = defaults.data(forKey: storageKey),
      let decoded = try? JSONDecoder().decode([String: ReadingSessionSnapshot].self, from: data)
    else { return [:] }
    return decoded
  }
}

enum DuoSplitDividerGeometry {
  static let minPaneWidth: CGFloat = 320
  static let dividerWidth: CGFloat = 14
  static let snapShares: [CGFloat] = [1.0 / 3.0, 0.4, 0.5, 0.6]
  static let snapTolerancePoints: CGFloat = 6
  static let defaultShareKey = "Helio.DuoDividerFeedShare"

  static func availablePaneWidth(totalWidth: CGFloat) -> CGFloat {
    max(0, totalWidth - dividerWidth)
  }

  static func canResize(totalWidth: CGFloat) -> Bool {
    availablePaneWidth(totalWidth: totalWidth) >= minPaneWidth * 2
  }

  static func clampedWidth(_ proposed: CGFloat, totalWidth: CGFloat) -> CGFloat {
    let available = availablePaneWidth(totalWidth: totalWidth)
    let maxWidth = max(minPaneWidth, available - minPaneWidth)
    return min(max(proposed, minPaneWidth), maxWidth)
  }

  static func share(forWidth width: CGFloat, totalWidth: CGFloat) -> CGFloat {
    let available = availablePaneWidth(totalWidth: totalWidth)
    guard available > 0 else { return 0.5 }
    return clampedWidth(width, totalWidth: totalWidth) / available
  }

  static func snappedShare(forWidth width: CGFloat, totalWidth: CGFloat) -> CGFloat {
    let available = availablePaneWidth(totalWidth: totalWidth)
    guard available > 0 else { return 0.5 }
    let clamped = clampedWidth(width, totalWidth: totalWidth)
    for landmark in snapShares {
      let targetWidth = available * landmark
      guard targetWidth >= minPaneWidth, available - targetWidth >= minPaneWidth else { continue }
      if abs(clamped - targetWidth) <= snapTolerancePoints {
        return landmark
      }
    }
    return clamped / available
  }

  static func resolvedFeedWidth(
    savedShare: CGFloat?,
    totalWidth: CGFloat,
    defaultWidth: CGFloat?,
  ) -> CGFloat? {
    guard canResize(totalWidth: totalWidth) else {
      return defaultWidth
    }
    guard let savedShare, savedShare.isFinite, savedShare > 0, savedShare < 1 else {
      return defaultWidth.map { clampedWidth($0, totalWidth: totalWidth) }
    }
    let available = availablePaneWidth(totalWidth: totalWidth)
    return clampedWidth(available * savedShare, totalWidth: totalWidth)
  }
}
