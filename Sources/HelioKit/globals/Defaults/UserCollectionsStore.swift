import Foundation
import os
import Synchronization

@Observable
final class UserCollectionsStore: @unchecked Sendable {
  static let shared = UserCollectionsStore()

  private static let logger = Logger(subsystem: "com.sertacozercan.helio", category: "UserCollectionsStore")
  private static let filteredSubredditsFileName = "filteredSubreddits.json"
  private static let likedButNotSubbedFileName = "likedButNotSubbed.json"
  private static let legacyFilteredKeys = ["filteredSubreddits", "Defaults_filteredSubreddits"]
  private static let legacyLikedKeys = ["likedButNotSubbed", "Defaults_likedButNotSubbed"]
  private static let legacyMigrationMarkerKey = "UserCollectionsStore.migratedFromUserDefaults.v1"

  private struct BackingState {
    var filteredSubreddits: [String]
    var filteredSubredditsSet: Set<String>
    var likedButNotSubbed: [Subreddit]
  }

  @ObservationIgnored private let directory: URL
  @ObservationIgnored private let userDefaults: UserDefaults
  @ObservationIgnored private let state: Mutex<BackingState>
  @ObservationIgnored private let writeLock = Mutex(())

  private var filteredSubredditsCache: [String]
  private var likedButNotSubbedCache: [Subreddit]

  nonisolated static var defaultDirectory: URL {
    URL.applicationSupportDirectory.appending(path: "Helio/UserCollections", directoryHint: .isDirectory)
  }

  init(
    directory: URL = UserCollectionsStore.defaultDirectory,
    userDefaults: UserDefaults = .standard,
  ) {
    self.directory = directory
    self.userDefaults = userDefaults

    let shouldCheckLegacy = !userDefaults.bool(forKey: Self.legacyMigrationMarkerKey)

    let loadedFiltered = Self.loadCollection(
      String.self,
      from: directory.appending(path: Self.filteredSubredditsFileName),
      legacyKeys: shouldCheckLegacy ? Self.legacyFilteredKeys : [],
      userDefaults: userDefaults,
    )

    let loadedLiked = Self.loadCollection(
      Subreddit.self,
      from: directory.appending(path: Self.likedButNotSubbedFileName),
      legacyKeys: shouldCheckLegacy ? Self.legacyLikedKeys : [],
      userDefaults: userDefaults,
    )

    filteredSubredditsCache = loadedFiltered.value
    likedButNotSubbedCache = loadedLiked.value
    state = Mutex(
      BackingState(
        filteredSubreddits: loadedFiltered.value,
        filteredSubredditsSet: Set(loadedFiltered.value),
        likedButNotSubbed: loadedLiked.value,
      ),
    )

    if shouldCheckLegacy {
      let filteredCompleted = completeMigration(
        result: loadedFiltered,
        fileName: Self.filteredSubredditsFileName,
        legacyKeys: Self.legacyFilteredKeys,
      )
      let likedCompleted = completeMigration(
        result: loadedLiked,
        fileName: Self.likedButNotSubbedFileName,
        legacyKeys: Self.legacyLikedKeys,
      )
      if filteredCompleted, likedCompleted {
        userDefaults.set(true, forKey: Self.legacyMigrationMarkerKey)
      }
    }
  }

  var filteredSubreddits: [String] {
    get {
      access(keyPath: \.filteredSubredditsCache)
      return state.withLock(\.filteredSubreddits)
    }
    set {
      setFilteredSubreddits(newValue)
    }
  }

  var likedButNotSubbed: [Subreddit] {
    get {
      access(keyPath: \.likedButNotSubbedCache)
      return state.withLock(\.likedButNotSubbed)
    }
    set {
      setLikedButNotSubbed(newValue)
    }
  }

  func isSubredditFiltered(_ subreddit: String) -> Bool {
    access(keyPath: \.filteredSubredditsCache)
    return state.withLock { $0.filteredSubredditsSet.contains(subreddit) }
  }

  func isLocallyFavorited(_ subreddit: Subreddit) -> Bool {
    access(keyPath: \.likedButNotSubbedCache)
    return state.withLock { $0.likedButNotSubbed.contains(subreddit) }
  }

  func addFilteredSubreddit(_ subreddit: String) {
    guard !subreddit.isEmpty else { return }
    let updated: [String]? = state.withLock { current in
      guard !current.filteredSubredditsSet.contains(subreddit) else { return nil }
      current.filteredSubreddits.append(subreddit)
      current.filteredSubredditsSet.insert(subreddit)
      return current.filteredSubreddits
    }
    guard let updated else { return }
    publishFilteredSubreddits(updated)
    _ = persistLatestFilteredSubreddits()
  }

  func removeFilteredSubreddit(at index: Int) {
    let updated: [String]? = state.withLock { current in
      guard current.filteredSubreddits.indices.contains(index) else { return nil }
      let removed = current.filteredSubreddits.remove(at: index)
      current.filteredSubredditsSet.remove(removed)
      return current.filteredSubreddits
    }
    guard let updated else { return }
    publishFilteredSubreddits(updated)
    _ = persistLatestFilteredSubreddits()
  }

  @discardableResult
  func toggleFilteredSubreddit(_ subreddit: String) -> Bool {
    let result: (isFiltered: Bool, updated: [String]) = state.withLock { current in
      if let index = current.filteredSubreddits.firstIndex(of: subreddit) {
        current.filteredSubreddits.remove(at: index)
        current.filteredSubredditsSet.remove(subreddit)
        return (false, current.filteredSubreddits)
      }
      current.filteredSubreddits.append(subreddit)
      current.filteredSubredditsSet.insert(subreddit)
      return (true, current.filteredSubreddits)
    }
    publishFilteredSubreddits(result.updated)
    _ = persistLatestFilteredSubreddits()
    return result.isFiltered
  }

  func setFilteredSubreddits(_ newValue: [String]) {
    state.withLock { current in
      current.filteredSubreddits = newValue
      current.filteredSubredditsSet = Set(newValue)
    }
    publishFilteredSubreddits(newValue)
    _ = persistLatestFilteredSubreddits()
  }

  @discardableResult
  func toggleLocalFavorite(_ subreddit: Subreddit) -> Bool {
    let result: (isLiked: Bool, updated: [Subreddit]) = state.withLock { current in
      let wasLiked = current.likedButNotSubbed.contains(subreddit)
      if wasLiked {
        current.likedButNotSubbed.removeAll { $0.id == subreddit.id }
      } else {
        current.likedButNotSubbed.append(subreddit)
      }
      return (!wasLiked, current.likedButNotSubbed)
    }
    publishLikedButNotSubbed(result.updated)
    _ = persistLatestLikedButNotSubbed()
    return result.isLiked
  }

  func setLikedButNotSubbed(_ newValue: [Subreddit]) {
    state.withLock { current in
      current.likedButNotSubbed = newValue
    }
    publishLikedButNotSubbed(newValue)
    _ = persistLatestLikedButNotSubbed()
  }

  func clearLikedButNotSubbed() {
    setLikedButNotSubbed([])
  }

  private func completeMigration(
    result: LoadedCollection<some Encodable>,
    fileName: String,
    legacyKeys: [String],
  ) -> Bool {
    switch result.legacyStatus {
    case .none:
      return true
    case .migrated:
      guard persist(result.value, to: fileName) else { return false }
      for key in legacyKeys {
        userDefaults.removeObject(forKey: key)
      }
      return true
    case .failedToDecode:
      return false
    }
  }

  private func publishFilteredSubreddits(_ newValue: [String]) {
    if Thread.isMainThread {
      withMutation(keyPath: \.filteredSubredditsCache) {
        filteredSubredditsCache = newValue
      }
    } else {
      Task { @MainActor [weak self] in
        guard let self else { return }
        let latest = state.withLock(\.filteredSubreddits)
        withMutation(keyPath: \.filteredSubredditsCache) {
          self.filteredSubredditsCache = latest
        }
      }
    }
  }

  private func publishLikedButNotSubbed(_ newValue: [Subreddit]) {
    if Thread.isMainThread {
      withMutation(keyPath: \.likedButNotSubbedCache) {
        likedButNotSubbedCache = newValue
      }
    } else {
      Task { @MainActor [weak self] in
        guard let self else { return }
        let latest = state.withLock(\.likedButNotSubbed)
        withMutation(keyPath: \.likedButNotSubbedCache) {
          self.likedButNotSubbedCache = latest
        }
      }
    }
  }

  @discardableResult
  private func persistLatestFilteredSubreddits() -> Bool {
    persist(to: Self.filteredSubredditsFileName) {
      state.withLock(\.filteredSubreddits)
    }
  }

  @discardableResult
  private func persistLatestLikedButNotSubbed() -> Bool {
    persist(to: Self.likedButNotSubbedFileName) {
      state.withLock(\.likedButNotSubbed)
    }
  }

  @discardableResult
  private func persist(_ value: some Encodable, to fileName: String) -> Bool {
    persist(to: fileName) { value }
  }

  @discardableResult
  private func persist(to fileName: String, latestValue: () -> some Encodable) -> Bool {
    writeLock.withLock { _ in
      do {
        let value = latestValue()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        try data.write(to: directory.appending(path: fileName), options: .atomic)
        return true
      } catch {
        Self.logger.error("Failed to persist \(fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        return false
      }
    }
  }

  private enum LegacyStatus {
    case none
    case migrated
    case failedToDecode
  }

  private struct LoadedCollection<Element> {
    let value: [Element]
    let legacyStatus: LegacyStatus
  }

  private static func loadCollection<Element: Decodable>(
    _ elementType: Element.Type,
    from fileURL: URL,
    legacyKeys: [String],
    userDefaults: UserDefaults,
  ) -> LoadedCollection<Element> {
    if FileManager.default.fileExists(atPath: fileURL.path) {
      do {
        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode([Element].self, from: data)
        return LoadedCollection(value: decoded, legacyStatus: .none)
      } catch {
        logger.error("Failed to read \(fileURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
      }
    }

    guard !legacyKeys.isEmpty else {
      return LoadedCollection(value: [], legacyStatus: .none)
    }

    var sawLegacyPayload = false
    for key in legacyKeys {
      guard let raw = userDefaults.object(forKey: key) else { continue }
      sawLegacyPayload = true
      if let decoded = decodeLegacyArray(elementType, from: raw) {
        return LoadedCollection(value: decoded, legacyStatus: .migrated)
      }
      logger.error("Failed to decode legacy UserDefaults key \(key, privacy: .public); preserving legacy data.")
    }

    return LoadedCollection(value: [], legacyStatus: sawLegacyPayload ? .failedToDecode : .none)
  }

  private static func decodeLegacyArray<Element: Decodable>(_ elementType: Element.Type, from raw: Any) -> [Element]? {
    if let typed = raw as? [Element] {
      return typed
    }

    let decoder = JSONDecoder()

    if let jsonStrings = raw as? [String] {
      var decodedElements: [Element] = []
      decodedElements.reserveCapacity(jsonStrings.count)
      for item in jsonStrings {
        guard let data = item.data(using: .utf8),
              let element = try? decoder.decode(Element.self, from: data)
        else {
          return nil
        }
        decodedElements.append(element)
      }
      return decodedElements
    }

    if let string = raw as? String, let data = string.data(using: .utf8),
       let decoded = try? decoder.decode([Element].self, from: data)
    {
      return decoded
    }

    if let data = raw as? Data, let decoded = try? decoder.decode([Element].self, from: data) {
      return decoded
    }

    if JSONSerialization.isValidJSONObject(raw),
       let data = try? JSONSerialization.data(withJSONObject: raw),
       let decoded = try? decoder.decode([Element].self, from: data)
    {
      return decoded
    }

    return nil
  }
}
