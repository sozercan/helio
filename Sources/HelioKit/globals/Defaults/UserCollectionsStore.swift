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
    var filteredRevision: UInt64 = 0
    var likedButNotSubbed: [Subreddit]
    var likedLoadFailed: Bool
    var likedRevision: UInt64 = 0
  }

  private struct RevisionedValue<Value> {
    let value: Value
    let revision: UInt64
  }

  private struct SnapshotWrite {
    let revision: UInt64
    let data: Data
  }

  private struct PendingWrites {
    var filtered: SnapshotWrite?
    var liked: SnapshotWrite?
    var minFilteredRevision: UInt64 = 0
    var minLikedRevision: UInt64 = 0
    var runningTask: Task<Void, Never>?
  }

  private struct WriteState {
    var lastWrittenFilteredRevision: UInt64 = 0
    var lastWrittenLikedRevision: UInt64 = 0
  }

  @ObservationIgnored private let directory: URL
  @ObservationIgnored private let userDefaults: UserDefaults
  @ObservationIgnored private let state: Mutex<BackingState>
  @ObservationIgnored private let writeLock = Mutex(WriteState())
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
    let updated: RevisionedValue<[String]>? = state.withLock { current in
      guard !current.filteredLoadFailed, !current.filteredSubredditsSet.contains(subreddit) else { return nil }
      current.filteredSubreddits.append(subreddit)
      current.filteredSubredditsSet.insert(subreddit)
      current.filteredRevision += 1
      return RevisionedValue(value: current.filteredSubreddits, revision: current.filteredRevision)
    }
    guard let updated else { return }
    publishFilteredSubreddits(updated.value)
    schedulePersist(filtered: updated)
  }

  func removeFilteredSubreddit(at index: Int) {
    let updated: RevisionedValue<[String]>? = state.withLock { current in
      guard !current.filteredLoadFailed, current.filteredSubreddits.indices.contains(index) else { return nil }
      let removed = current.filteredSubreddits.remove(at: index)
      current.filteredSubredditsSet.remove(removed)
      current.filteredRevision += 1
      return RevisionedValue(value: current.filteredSubreddits, revision: current.filteredRevision)
    }
    guard let updated else { return }
    publishFilteredSubreddits(updated.value)
    schedulePersist(filtered: updated)
  }

  @discardableResult
  func toggleFilteredSubreddit(_ subreddit: String) -> Bool {
    let result: (isFiltered: Bool, updated: RevisionedValue<[String]>)? = state.withLock { current in
      guard !current.filteredLoadFailed else { return nil }
      current.filteredRevision += 1
      if let index = current.filteredSubreddits.firstIndex(of: subreddit) {
        current.filteredSubreddits.remove(at: index)
        current.filteredSubredditsSet.remove(subreddit)
        return (false, RevisionedValue(value: current.filteredSubreddits, revision: current.filteredRevision))
      }
      current.filteredSubreddits.append(subreddit)
      current.filteredSubredditsSet.insert(subreddit)
      return (true, RevisionedValue(value: current.filteredSubreddits, revision: current.filteredRevision))
    }
    guard let result else { return false }
    publishFilteredSubreddits(result.updated.value)
    schedulePersist(filtered: result.updated)
    return result.isFiltered
  }

  func setFilteredSubreddits(_ newValue: [String], allowOverwriteAfterLoadError: Bool = false) {
    let updated: RevisionedValue<[String]>? = state.withLock { current in
      if current.filteredLoadFailed, !allowOverwriteAfterLoadError {
        return nil
      }
      current.filteredLoadFailed = false
      current.filteredSubreddits = newValue
      current.filteredSubredditsSet = Set(newValue)
      current.filteredRevision += 1
      return RevisionedValue(value: current.filteredSubreddits, revision: current.filteredRevision)
    }
    guard let updated else { return }
    publishFilteredSubreddits(updated.value)
    schedulePersist(filtered: updated)
  }

  @discardableResult
  func toggleLocalFavorite(_ subreddit: Subreddit) -> Bool {
    let result: (isLiked: Bool, updated: RevisionedValue<[Subreddit]>)? = state.withLock { current in
      guard !current.likedLoadFailed else { return nil }
      let wasLiked = current.likedButNotSubbed.contains(subreddit)
      if wasLiked {
        current.likedButNotSubbed.removeAll { $0.id == subreddit.id }
      } else {
        current.likedButNotSubbed.append(subreddit)
      }
      current.likedRevision += 1
      return (!wasLiked, RevisionedValue(value: current.likedButNotSubbed, revision: current.likedRevision))
    }
    guard let result else { return false }
    publishLikedButNotSubbed(result.updated.value)
    schedulePersist(liked: result.updated)
    return result.isLiked
  }

  func setLikedButNotSubbed(_ newValue: [Subreddit], allowOverwriteAfterLoadError: Bool = false) {
    let updated: RevisionedValue<[Subreddit]>? = state.withLock { current in
      if current.likedLoadFailed, !allowOverwriteAfterLoadError {
        return nil
      }
      current.likedLoadFailed = false
      current.likedButNotSubbed = newValue
      current.likedRevision += 1
      return RevisionedValue(value: current.likedButNotSubbed, revision: current.likedRevision)
    }
    guard let updated else { return }
    publishLikedButNotSubbed(updated.value)
    schedulePersist(liked: updated)
  }

  func clearLikedButNotSubbed() {
    setLikedButNotSubbed([], allowOverwriteAfterLoadError: true)
  }

  func resetAll() {
    let revisions: (filtered: UInt64, liked: UInt64) = state.withLock { current in
      current.filteredLoadFailed = false
      current.filteredSubreddits = []
      current.filteredSubredditsSet = []
      current.filteredRevision += 1
      current.likedLoadFailed = false
      current.likedButNotSubbed = []
      current.likedRevision += 1
      return (current.filteredRevision, current.likedRevision)
    }
    pendingWrites.withLock { pending in
      if revisions.filtered > pending.minFilteredRevision {
        pending.minFilteredRevision = revisions.filtered
      }
      if let existing = pending.filtered, existing.revision <= revisions.filtered {
        pending.filtered = nil
      }
      if revisions.liked > pending.minLikedRevision {
        pending.minLikedRevision = revisions.liked
      }
      if let existing = pending.liked, existing.revision <= revisions.liked {
        pending.liked = nil
      }
    }
    publishFilteredSubreddits([])
    publishLikedButNotSubbed([])
    let emptyData = Data("[]".utf8)
    _ = writeSnapshot(
      SnapshotWrite(revision: revisions.filtered, data: emptyData),
      isFiltered: true,
      to: Self.filteredSubredditsFileName,
    )
    _ = writeSnapshot(
      SnapshotWrite(revision: revisions.liked, data: emptyData),
      isFiltered: false,
      to: Self.likedButNotSubbedFileName,
    )
    for key in Self.legacyFilteredKeys + Self.legacyLikedKeys {
      userDefaults.removeObject(forKey: key)
    }
    userDefaults.set(true, forKey: Self.legacyMigrationMarkerKey)
  }

  func exportEntries() -> [String: Any] {
    let snapshot = state.withLock {
      (
        filtered: $0.filteredSubreddits,
        filteredFailed: $0.filteredLoadFailed,
        liked: $0.likedButNotSubbed,
        likedFailed: $0.likedLoadFailed,
      )
    }
    var entries: [String: Any] = [:]
    let hasLegacyFiltered = Self.legacyFilteredKeys.contains { userDefaults.object(forKey: $0) != nil }
    if !snapshot.filteredFailed, !hasLegacyFiltered {
      entries["filteredSubreddits"] = snapshot.filtered
    }
    let hasLegacyLiked = Self.legacyLikedKeys.contains { userDefaults.object(forKey: $0) != nil }
    if !snapshot.likedFailed, !hasLegacyLiked {
      let encoder = JSONEncoder()
      let encodedLiked = snapshot.liked.compactMap { sub -> String? in
        guard let data = try? encoder.encode(sub) else { return nil }
        return String(bytes: data, encoding: .utf8)
      }
      entries["likedButNotSubbed"] = encodedLiked
    }
    return entries
  }

  func importEntries(from jsonObject: [String: Any]) {
    var importedFiltered = false
    for key in Self.legacyFilteredKeys {
      if let raw = jsonObject[key], let decoded = Self.decodeLegacyArray(String.self, from: raw) {
        setFilteredSubreddits(decoded, allowOverwriteAfterLoadError: true)
        importedFiltered = true
        break
      }
    }
    var importedLiked = false
    for key in Self.legacyLikedKeys {
      if let raw = jsonObject[key], let decoded = Self.decodeLegacyArray(Subreddit.self, from: raw) {
        setLikedButNotSubbed(decoded, allowOverwriteAfterLoadError: true)
        importedLiked = true
        break
      }
    }
    if importedFiltered {
      for key in Self.legacyFilteredKeys {
        userDefaults.removeObject(forKey: key)
      }
    }
    if importedLiked {
      for key in Self.legacyLikedKeys {
        userDefaults.removeObject(forKey: key)
      }
    }
  }

  func flushPendingWrites() async {
    while let task = pendingWrites.withLock(\.runningTask) {
      await task.value
    }
  }

  private func schedulePersist(
    filtered: RevisionedValue<[String]>? = nil,
    liked: RevisionedValue<[Subreddit]>? = nil,
  ) {
    let filteredSnapshot: SnapshotWrite? = filtered.flatMap { entry in
      do {
        return try SnapshotWrite(revision: entry.revision, data: JSONEncoder().encode(entry.value))
      } catch {
        Self.logger.error("Failed to encode \(Self.filteredSubredditsFileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        return nil
      }
    }
    let likedSnapshot: SnapshotWrite? = liked.flatMap { entry in
      do {
        return try SnapshotWrite(revision: entry.revision, data: JSONEncoder().encode(entry.value))
      } catch {
        Self.logger.error("Failed to encode \(Self.likedButNotSubbedFileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        return nil
      }
    }
    guard filteredSnapshot != nil || likedSnapshot != nil else { return }
    pendingWrites.withLock { pending in
      if let filteredSnapshot,
         filteredSnapshot.revision > pending.minFilteredRevision,
         pending.filtered.map({ filteredSnapshot.revision > $0.revision }) ?? true
      {
        pending.filtered = filteredSnapshot
      }
      if let likedSnapshot,
         likedSnapshot.revision > pending.minLikedRevision,
         pending.liked.map({ likedSnapshot.revision > $0.revision }) ?? true
      {
        pending.liked = likedSnapshot
      }
      guard pending.filtered != nil || pending.liked != nil, pending.runningTask == nil else { return }
      pending.runningTask = Task(priority: .utility) { [weak self] in
        self?.drainPendingWrites()
      }
    }
  }

  private func drainPendingWrites() {
    while true {
      let batch: (filtered: SnapshotWrite?, liked: SnapshotWrite?) = pendingWrites.withLock { pending in
        let result = (pending.filtered, pending.liked)
        pending.filtered = nil
        pending.liked = nil
        if result.0 == nil, result.1 == nil {
          pending.runningTask = nil
        }
        return result
      }
      if batch.filtered == nil, batch.liked == nil {
        return
      }
      if let filtered = batch.filtered {
        _ = writeSnapshot(filtered, isFiltered: true, to: Self.filteredSubredditsFileName)
      }
      if let liked = batch.liked {
        _ = writeSnapshot(liked, isFiltered: false, to: Self.likedButNotSubbedFileName)
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
  private func persist(_ value: some Encodable, to fileName: String) -> Bool {
    do {
      let data = try JSONEncoder().encode(value)
      return writeData(data, to: fileName)
    } catch {
      Self.logger.error("Failed to persist \(fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
      return false
    }
  }

  @discardableResult
  private func writeSnapshot(_ snapshot: SnapshotWrite, isFiltered: Bool, to fileName: String) -> Bool {
    writeLock.withLock { writeState in
      let lastWritten = isFiltered ? writeState.lastWrittenFilteredRevision : writeState.lastWrittenLikedRevision
      guard snapshot.revision > lastWritten else { return true }
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try snapshot.data.write(to: directory.appending(path: fileName), options: .atomic)
        if isFiltered {
          writeState.lastWrittenFilteredRevision = snapshot.revision
        } else {
          writeState.lastWrittenLikedRevision = snapshot.revision
        }
        return true
      } catch {
        Self.logger.error("Failed to persist \(fileName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        return false
      }
    }
  }

  @discardableResult
  private func writeData(_ data: Data, to fileName: String) -> Bool {
    writeLock.withLock { _ in
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
