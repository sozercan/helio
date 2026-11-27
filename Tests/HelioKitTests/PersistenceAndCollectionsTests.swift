import CoreData
import Foundation
import Testing
@testable import HelioKit

@MainActor
struct PersistenceControllerTests {
  private func makeTempDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "PersistenceControllerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func closeStores(_ controller: PersistenceController) {
    let coordinator = controller.container.persistentStoreCoordinator
    for store in coordinator.persistentStores {
      try? coordinator.remove(store)
    }
  }

  private func makeIncompatibleModel() -> NSManagedObjectModel {
    let entity = NSEntityDescription()
    entity.name = "CachedSub"
    entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
    let attribute = NSAttributeDescription()
    attribute.name = "requiredUpgradeField"
    attribute.attributeType = .integer64AttributeType
    attribute.isOptional = false
    entity.properties = [attribute]
    let model = NSManagedObjectModel()
    model.entities = [entity]
    return model
  }

  @Test func loadsHealthyOnDiskStorePersistently() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let storeURL = dir.appending(path: "Helio.sqlite")

    let controller = PersistenceController(
      managedObjectModel: AccountListSyncAuthorizationTests.model,
      storeURL: storeURL,
    )
    defer { closeStores(controller) }

    #expect(controller.storeLoadStatus == .persistent)
    #expect(controller.lastLoadError == nil)
    #expect(controller.container.persistentStoreCoordinator.persistentStores.count == 1)
    #expect(controller.container.persistentStoreCoordinator.persistentStores.first?.type == NSSQLiteStoreType)
  }

  @Test func recreatesCorruptedOnDiskStoreInsteadOfCrashing() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let storeURL = dir.appending(path: "Helio.sqlite")
    try Data("corrupted-sqlite-header".utf8).write(to: storeURL)

    let controller = PersistenceController(
      managedObjectModel: AccountListSyncAuthorizationTests.model,
      storeURL: storeURL,
    )
    defer { closeStores(controller) }

    #expect(controller.storeLoadStatus == .recreatedAfterError)
    #expect(controller.lastLoadError != nil)
    #expect(controller.container.persistentStoreCoordinator.persistentStores.count == 1)
    #expect(controller.container.persistentStoreCoordinator.persistentStores.first?.type == NSSQLiteStoreType)
  }

  @Test func preservesStoreFilesOnNonCorruptionLoadError() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let storeURL = dir.appending(path: "Helio.sqlite")

    let initial = PersistenceController(
      managedObjectModel: AccountListSyncAuthorizationTests.model,
      storeURL: storeURL,
    )
    let sub = NSEntityDescription.insertNewObject(forEntityName: "CachedSub", into: initial.container.viewContext)
    sub.setValue("t5_keep", forKey: "uuid")
    try initial.container.viewContext.save()
    closeStores(initial)
    let originalData = try Data(contentsOf: storeURL)

    let incompatible = PersistenceController(
      managedObjectModel: makeIncompatibleModel(),
      storeURL: storeURL,
    )
    defer { closeStores(incompatible) }

    #expect(incompatible.storeLoadStatus == .inMemoryFallback)
    #expect(incompatible.lastLoadError != nil)
    #expect(incompatible.container.persistentStoreCoordinator.persistentStores.first?.type == NSInMemoryStoreType)
    #expect(FileManager.default.fileExists(atPath: storeURL.path))
    #expect(try Data(contentsOf: storeURL) == originalData)
  }

  @Test func fallsBackToInMemoryStoreWhenPersistentPathCannotBeOpened() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let blockerFile = dir.appending(path: "not-a-directory")
    try Data("blocker".utf8).write(to: blockerFile)
    let blockedURL = blockerFile.appending(path: "Helio.sqlite")

    let controller = PersistenceController(
      managedObjectModel: AccountListSyncAuthorizationTests.model,
      storeURL: blockedURL,
    )
    defer { closeStores(controller) }

    #expect(controller.storeLoadStatus == .inMemoryFallback)
    #expect(controller.lastLoadError != nil)
    #expect(controller.container.persistentStoreCoordinator.persistentStores.count == 1)
    #expect(controller.container.persistentStoreCoordinator.persistentStores.first?.type == NSInMemoryStoreType)
  }
}

struct UserCollectionsStoreTests {
  private func makeTempDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "UserCollectionsStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func makeUserDefaults() throws -> (suiteName: String, defaults: UserDefaults) {
    let suiteName = "com.sertacozercan.helio.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return (suiteName, defaults)
  }

  private func makeSubreddit(id: String, name: String) throws -> Subreddit {
    let json: [String: Any] = [
      "id": id,
      "name": "t5_\(id)",
      "display_name": name,
      "url": "/r/\(name)/",
      "title": name,
      "public_description": "",
    ]
    let data = try JSONDecoder().decode(SubredditData.self, from: JSONSerialization.data(withJSONObject: json))
    return Subreddit(data: data)
  }

  @Test func migratesLegacyDefaultsArrayFormatOnceAndIsIdempotent() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let (suiteName, defaults) = try makeUserDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let subA = try makeSubreddit(id: "abc123", name: "swift")
    let subB = try makeSubreddit(id: "def456", name: "ios")
    let encodedSubA = try #require(String(bytes: JSONEncoder().encode(subA), encoding: .utf8))
    let encodedSubB = try #require(String(bytes: JSONEncoder().encode(subB), encoding: .utf8))
    defaults.set(["pics", "funny"], forKey: "filteredSubreddits")
    defaults.set([encodedSubA, encodedSubB], forKey: "likedButNotSubbed")

    let firstStore = UserCollectionsStore(directory: dir, userDefaults: defaults)
    #expect(firstStore.filteredSubreddits == ["pics", "funny"])
    #expect(firstStore.isSubredditFiltered("pics"))
    #expect(!firstStore.isSubredditFiltered("swift"))
    #expect(firstStore.likedButNotSubbed.map(\.id) == [subA.id, subB.id])
    #expect(firstStore.isLocallyFavorited(subA))
    #expect(firstStore.isLocallyFavorited(subB))
    #expect(defaults.object(forKey: "filteredSubreddits") == nil)
    #expect(defaults.object(forKey: "likedButNotSubbed") == nil)

    firstStore.removeFilteredSubreddit(at: 0)
    firstStore.clearLikedButNotSubbed()

    defaults.set(["should-not-overwrite"], forKey: "filteredSubreddits")
    let reopened = UserCollectionsStore(directory: dir, userDefaults: defaults)
    #expect(reopened.filteredSubreddits == ["funny"])
    #expect(reopened.likedButNotSubbed.isEmpty)
  }

  @Test func retainsLegacyKeysWhenDecodingFails() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let (suiteName, defaults) = try makeUserDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    defaults.set(["{invalid-json"], forKey: "likedButNotSubbed")

    let store = UserCollectionsStore(directory: dir, userDefaults: defaults)
    #expect(store.likedButNotSubbed.isEmpty)
    #expect(defaults.stringArray(forKey: "likedButNotSubbed") == ["{invalid-json"])
    #expect(!defaults.bool(forKey: "UserCollectionsStore.migratedFromUserDefaults.v1"))
  }

  @Test func persistsFilteredSubredditsAndLocalFavoritesAcrossReopen() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let (suiteName, defaults) = try makeUserDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let subA = try makeSubreddit(id: "subA", name: "apple")
    let subB = try makeSubreddit(id: "subB", name: "mac")

    let store = UserCollectionsStore(directory: dir, userDefaults: defaults)
    store.addFilteredSubreddit("news")
    store.addFilteredSubreddit("news")
    #expect(store.toggleFilteredSubreddit("gaming"))
    #expect(store.filteredSubreddits == ["news", "gaming"])
    #expect(!store.toggleFilteredSubreddit("news"))
    #expect(store.filteredSubreddits == ["gaming"])

    #expect(store.toggleLocalFavorite(subA))
    #expect(store.toggleLocalFavorite(subB))
    #expect(!store.toggleLocalFavorite(subA))
    #expect(store.likedButNotSubbed.map(\.id) == [subB.id])

    let reopened = UserCollectionsStore(directory: dir, userDefaults: defaults)
    #expect(reopened.filteredSubreddits == ["gaming"])
    #expect(reopened.isSubredditFiltered("gaming"))
    #expect(reopened.likedButNotSubbed.map(\.id) == [subB.id])
    #expect(reopened.isLocallyFavorited(subB))
    #expect(!reopened.isLocallyFavorited(subA))
  }
}
