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

  static let managedBackupKeys: Set<String> = Set(legacyFilteredKeys + legacyLikedKeys + [legacyMigrationMarkerKey])

  private struct BackingState {
    var filteredSubreddits: [String]
    var filteredSubredditsSet: Set<String>
    var filteredLoadFailed: Bool
    var likedButNotSubbed: [Subreddit]
    var likedLoadFailed: Bool
  }

  private struct PendingWrites {
    var filteredDirty = false
    var likedDirty = false
    var runningTask: Task<Void, Never>?
  }

  @ObservationIgnored private let directory: URL
  @ObservationIgnored private let userDefaults: UserDefaults
  @ObservationIgnored private let state: Mutex<BackingState>
  @ObservationIgnored private let writeLock = Mutex(())
  @ObservationIgnored private let pendingWrites = Mutex(PendingWrites())

  private var filteredSubredditsCache: [String]
  private var likedButNotSubbedCache: [Subreddit]

  nonisolated static var defaultDirectory: URL {
    URL.applicationSupportDirectory.appending(path: "Helio/UserCollections", directoryHint: .isDirectory)
  }

  var hasFilteredLoadError: Bool {
    state.withLock(\.filteredLoadFailed)
  }

  var hasLikedLoadError: Bool {
    state.withLock(\.likedLoadFailed)
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
        filteredLoadFailed: loadedFiltered.fileLoadFailed,
        likedButNotSubbed: loadedLiked.value,
        likedLoadFailed: loadedLiked.fileLoadFailed,
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
      guard !current.filteredLoadFailed, !current.filteredSubredditsSet.contains(subreddit) else { return nil }
      current.filteredSubreddits.append(subreddit)
      current.filteredSubredditsSet.insert(subreddit)
      return current.filteredSubreddits
    }
    guard let updated else { return }
    publishFilteredSubreddits(updated)
    schedulePersist(filtered: true)
  }

  func removeFilteredSubreddit(at index: Int) {
    let updated: [String]? = state.withLock { current in
      guard !current.filteredLoadFailed, current.filteredSubreddits.indices.contains(index) else { return nil }
      let removed = current.filteredSubreddits.remove(at: index)
      current.filteredSubredditsSet.remove(removed)
      return current.filteredSubreddits
    }
    guard let updated else { return }
    publishFilteredSubreddits(updated)
    schedulePersist(filtered: true)
  }

  @discardableResult
  func toggleFilteredSubreddit(_ subreddit: String) -> Bool {
    let result: (isFiltered: Bool, updated: [String])? = state.withLock { current in
      guard !current.filteredLoadFailed else { return nil }
      if let index = current.filteredSubreddits.firstIndex(of: subreddit) {
        current.filteredSubreddits.remove(at: index)
        current.filteredSubredditsSet.remove(subreddit)
        return (false, current.filteredSubreddits)
      }
      current.filteredSubreddits.append(subreddit)
      current.filteredSubredditsSet.insert(subreddit)
      return (true, current.filteredSubreddits)
    }
    guard let result else { return false }
    publishFilteredSubreddits(result.updated)
    schedulePersist(filtered: true)
    return result.isFiltered
  }

  func setFilteredSubreddits(_ newValue: [String], allowOverwriteAfterLoadError: Bool = false) {
    let updated: [String]? = state.withLock { current in
      if current.filteredLoadFailed, !allowOverwriteAfterLoadError {
        return nil
      }
      current.filteredLoadFailed = false
      current.filteredSubreddits = newValue
      current.filteredSubredditsSet = Set(newValue)
      return current.filteredSubreddits
    }
    guard let updated else { return }
    publishFilteredSubreddits(updated)
    schedulePersist(filtered: true)
  }

  @discardableResult
  func toggleLocalFavorite(_ subreddit: Subreddit) -> Bool {
    let result: (isLiked: Bool, updated: [Subreddit])? = state.withLock { current in
      guard !current.likedLoadFailed else { return nil }
      let wasLiked = current.likedButNotSubbed.contains(subreddit)
      if wasLiked {
        current.likedButNotSubbed.removeAll { $0.id == subreddit.id }
      } else {
        current.likedButNotSubbed.append(subreddit)
      }
      return (!wasLiked, current.likedButNotSubbed)
    }
    guard let result else { return false }
    publishLikedButNotSubbed(result.updated)
    schedulePersist(liked: true)
    return result.isLiked
  }

  func setLikedButNotSubbed(_ newValue: [Subreddit], allowOverwriteAfterLoadError: Bool = false) {
    let updated: [Subreddit]? = state.withLock { current in
      if current.likedLoadFailed, !allowOverwriteAfterLoadError {
        return nil
      }
      current.likedLoadFailed = false
      current.likedButNotSubbed = newValue
      return current.likedButNotSubbed
    }
    guard let updated else { return }
    publishLikedButNotSubbed(updated)
    schedulePersist(liked: true)
  }

  func clearLikedButNotSubbed() {
    setLikedButNotSubbed([], allowOverwriteAfterLoadError: true)
  }

  func resetAll() {
    state.withLock { current in
      current.filteredLoadFailed = false
      current.filteredSubreddits = []
      current.filteredSubredditsSet = []
      current.likedLoadFailed = false
      current.likedButNotSubbed = []
    }
    publishFilteredSubreddits([])
    publishLikedButNotSubbed([])
    _ = persistLatestFilteredSubreddits()
    _ = persistLatestLikedButNotSubbed()
    for key in Self.legacyFilteredKeys + Self.legacyLikedKeys {
      userDefaults.removeObject(forKey: key)
    }
    userDefaults.set(true, forKey: Self.legacyMigrationMarkerKey)
  }

  func exportEntries() -> [String: Any] {
    let snapshot = state.withLock { ($0.filteredSubreddits, $0.likedButNotSubbed) }
    var entries: [String: Any] = ["filteredSubreddits": snapshot.0]
    let encoder = JSONEncoder()
    let encodedLiked = snapshot.1.compactMap { sub -> String? in
      guard let data = try? encoder.encode(sub) else { return nil }
      return String(bytes: data, encoding: .utf8)
    }
    entries["likedButNotSubbed"] = encodedLiked
    return entries
  }

  func importEntries(from jsonObject: [String: Any]) {
    for key in Self.legacyFilteredKeys {
      if let raw = jsonObject[key], let decoded = Self.decodeLegacyArray(String.self, from: raw) {
        setFilteredSubreddits(decoded, allowOverwriteAfterLoadError: true)
        break
      }
    }
    for key in Self.legacyLikedKeys {
      if let raw = jsonObject[key], let decoded = Self.decodeLegacyArray(Subreddit.self, from: raw) {
        setLikedButNotSubbed(decoded, allowOverwriteAfterLoadError: true)
        break
      }
    }
    userDefaults.set(true, forKey: Self.legacyMigrationMarkerKey)
  }

  func flushPendingWrites() async {
    while let task = pendingWrites.withLock(\.runningTask) {
      await task.value
    }
  }

  private func schedulePersist(filtered: Bool = false, liked: Bool = false) {
    pendingWrites.withLock { pending in
      if filtered {
        pending.filteredDirty = true
      }
      if liked {
        pending.likedDirty = true
      }
      guard pending.runningTask == nil else { return }
      pending.runningTask = Task(priority: .utility) { [weak self] in
        self?.drainPendingWrites()
      }
    }
  }

  private func drainPendingWrites() {
    while true {
      let batch: (filtered: Bool, liked: Bool) = pendingWrites.withLock { pending in
        let result = (pending.filteredDirty, pending.likedDirty)
        pending.filteredDirty = false
        pending.likedDirty = false
        if !result.0, !result.1 {
          pending.runningTask = nil
        }
        return result
      }
      if !batch.filtered, !batch.liked {
        return
      }
      if batch.filtered {
        _ = persistLatestFilteredSubreddits()
      }
      if batch.liked {
        _ = persistLatestLikedButNotSubbed()
      }
    }
  }

  private func completeMigration(
    result: LoadedCollection<some Encodable>,
    fileName: String,
    legacyKeys: [String],
  ) -> Bool {
    switch result.legacyStatus {
    case .none:
      return !result.fileLoadFailed
    case let .cleanupLegacyOnly(removableKeys):
      for key in removableKeys {
        userDefaults.removeObject(forKey: key)
      }
      return !result.hasUndecodableLegacy
    case let .migrated(removableKeys):
      guard persist(result.value, to: fileName) else { return false }
      for key in removableKeys {
        userDefaults.removeObject(forKey: key)
      }
      return !result.hasUndecodableLegacy
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
    case cleanupLegacyOnly([String])
    case migrated([String])
    case failedToDecode
  }

  private struct LoadedCollection<Element> {
    let value: [Element]
    let legacyStatus: LegacyStatus
    let fileLoadFailed: Bool
    let hasUndecodableLegacy: Bool
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
        var removableLegacyKeys: [String] = []
        var hasUndecodableLegacy = false
        for key in legacyKeys {
          guard let raw = userDefaults.object(forKey: key) else { continue }
          if decodeLegacyArray(elementType, from: raw) != nil {
            removableLegacyKeys.append(key)
          } else {
            hasUndecodableLegacy = true
            logger.error("Failed to decode legacy UserDefaults key \(key, privacy: .public); preserving legacy data.")
          }
        }
        let status: LegacyStatus = removableLegacyKeys.isEmpty && !hasUndecodableLegacy
          ? .none
          : .cleanupLegacyOnly(removableLegacyKeys)
        return LoadedCollection(
          value: decoded,
          legacyStatus: status,
          fileLoadFailed: false,
          hasUndecodableLegacy: hasUndecodableLegacy,
        )
      } catch {
        logger.error("Failed to read \(fileURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        return LoadedCollection(
          value: [],
          legacyStatus: .none,
          fileLoadFailed: true,
          hasUndecodableLegacy: false,
        )
      }
    }

    guard !legacyKeys.isEmpty else {
      return LoadedCollection(value: [], legacyStatus: .none, fileLoadFailed: false, hasUndecodableLegacy: false)
    }

    var decodedValue: [Element]?
    var removableLegacyKeys: [String] = []
    var hasUndecodableLegacy = false
    for key in legacyKeys {
      guard let raw = userDefaults.object(forKey: key) else { continue }
      if let decoded = decodeLegacyArray(elementType, from: raw) {
        if decodedValue == nil {
          decodedValue = decoded
        }
        removableLegacyKeys.append(key)
      } else {
        hasUndecodableLegacy = true
        logger.error("Failed to decode legacy UserDefaults key \(key, privacy: .public); preserving legacy data.")
      }
    }

    if let decodedValue {
      return LoadedCollection(
        value: decodedValue,
        legacyStatus: .migrated(removableLegacyKeys),
        fileLoadFailed: false,
        hasUndecodableLegacy: hasUndecodableLegacy,
      )
    }

    return LoadedCollection(
      value: [],
      legacyStatus: hasUndecodableLegacy ? .failedToDecode : .none,
      fileLoadFailed: false,
      hasUndecodableLegacy: hasUndecodableLegacy,
    )
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
