import Foundation

struct ReadingSessionSnapshot: Equatable, Codable, Sendable {
  let accountID: UUID
  let feedName: String
  let savedAt: Date
}

enum ReadingSessionStore {
  private static let storageKey = "Helio.ReadingSessionSnapshots.v1"

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
  static let snapShares: [CGFloat] = [1.0 / 3.0, 0.4, 0.5, 0.6]
  static let snapTolerancePoints: CGFloat = 6
  static let defaultShareKey = "Helio.DuoDividerFeedShare"

  static func clampedWidth(_ proposed: CGFloat, totalWidth: CGFloat) -> CGFloat {
    let maxWidth = max(minPaneWidth, totalWidth - minPaneWidth)
    return min(max(proposed, minPaneWidth), maxWidth)
  }

  static func share(forWidth width: CGFloat, totalWidth: CGFloat) -> CGFloat {
    guard totalWidth > 0 else { return 0.5 }
    return clampedWidth(width, totalWidth: totalWidth) / totalWidth
  }

  static func snappedShare(forWidth width: CGFloat, totalWidth: CGFloat) -> CGFloat {
    guard totalWidth > 0 else { return 0.5 }
    let clamped = clampedWidth(width, totalWidth: totalWidth)
    for landmark in snapShares {
      let targetWidth = totalWidth * landmark
      guard targetWidth >= minPaneWidth, totalWidth - targetWidth >= minPaneWidth else { continue }
      if abs(clamped - targetWidth) <= snapTolerancePoints {
        return landmark
      }
    }
    return clamped / totalWidth
  }

  static func resolvedFeedWidth(
    savedShare: CGFloat?,
    totalWidth: CGFloat,
    defaultWidth: CGFloat?,
  ) -> CGFloat? {
    guard totalWidth >= minPaneWidth * 2, let savedShare, savedShare.isFinite, savedShare > 0, savedShare < 1 else {
      return defaultWidth
    }
    return clampedWidth(totalWidth * savedShare, totalWidth: totalWidth)
  }
}
