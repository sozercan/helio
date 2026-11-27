import CoreData
import Foundation
import os

struct PersistenceController {
  enum StoreLoadStatus: Equatable {
    case persistent
    case recreatedAfterError
    case inMemoryFallback
  }

  private static let logger = Logger(subsystem: "com.sertacozercan.helio", category: "Persistence")

  static let shared = PersistenceController()

  let container: NSPersistentCloudKitContainer
  let primaryBGContext: NSManagedObjectContext
  let accountListsContext: NSManagedObjectContext
  let storeLoadStatus: StoreLoadStatus
  let lastLoadError: String?

  init(inMemory: Bool = false) {
    let container = NSPersistentCloudKitContainer(name: "Helio")
    let outcome = Self.loadStores(in: container, inMemory: inMemory)
    self.container = container
    self.storeLoadStatus = outcome.status
    self.lastLoadError = outcome.errorDescription

    accountListsContext = container.newBackgroundContext()
    accountListsContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    accountListsContext.automaticallyMergesChangesFromParent = true

    self.primaryBGContext = container.newBackgroundContext()
    self.primaryBGContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    self.primaryBGContext.automaticallyMergesChangesFromParent = true
    container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    container.viewContext.automaticallyMergesChangesFromParent = true
  }

  init(
    name: String = "Helio",
    managedObjectModel: NSManagedObjectModel,
    storeURL: URL?,
    inMemory: Bool = false,
  ) {
    let container = NSPersistentCloudKitContainer(name: name, managedObjectModel: managedObjectModel)
    if let storeURL, let description = container.persistentStoreDescriptions.first {
      description.url = storeURL
      description.cloudKitContainerOptions = nil
    }
    let outcome = Self.loadStores(in: container, inMemory: inMemory)
    self.container = container
    self.storeLoadStatus = outcome.status
    self.lastLoadError = outcome.errorDescription

    accountListsContext = container.newBackgroundContext()
    accountListsContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    accountListsContext.automaticallyMergesChangesFromParent = true

    self.primaryBGContext = container.newBackgroundContext()
    self.primaryBGContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    self.primaryBGContext.automaticallyMergesChangesFromParent = true
    container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    container.viewContext.automaticallyMergesChangesFromParent = true
  }

  private struct LoadOutcome {
    let status: StoreLoadStatus
    let errorDescription: String?
  }

  private static func loadStores(in container: NSPersistentCloudKitContainer, inMemory: Bool) -> LoadOutcome {
    if inMemory {
      configureInMemory(container)
      let errors = attemptLoad(in: container)
      if let firstError = errors.first {
        logger.error("Failed to load in-memory persistent store: \(firstError.localizedDescription, privacy: .public)")
        return LoadOutcome(status: .inMemoryFallback, errorDescription: firstError.localizedDescription)
      }
      return LoadOutcome(status: .inMemoryFallback, errorDescription: nil)
    }

    let originalDescriptions = container.persistentStoreDescriptions.map { $0.copy() as? NSPersistentStoreDescription ?? $0 }
    let initialErrors = attemptLoad(in: container)
    guard let initialError = initialErrors.first else {
      return LoadOutcome(status: .persistent, errorDescription: nil)
    }

    logger.error("Failed to load persistent store: \(initialError.localizedDescription, privacy: .public).")
    removeLoadedStores(from: container)

    if isCorruptionError(initialError), recreateStoreFiles(for: originalDescriptions) {
      container.persistentStoreDescriptions = originalDescriptions
      let retryErrors = attemptLoad(in: container)
      if retryErrors.isEmpty {
        logger.warning("Recovered Core Data store by recreating corrupted local store files.")
        return LoadOutcome(status: .recreatedAfterError, errorDescription: initialError.localizedDescription)
      }
      if let retryError = retryErrors.first {
        logger.error("Persistent store recreation failed: \(retryError.localizedDescription, privacy: .public). Falling back to in-memory store.")
      }
      removeLoadedStores(from: container)
    } else if !isCorruptionError(initialError) {
      logger.warning("Preserving existing persistent store files because the load error does not indicate corruption. Falling back to in-memory store.")
    }

    configureInMemory(container)
    let fallbackErrors = attemptLoad(in: container)
    if let fallbackError = fallbackErrors.first {
      logger.error("In-memory fallback store failed to load: \(fallbackError.localizedDescription, privacy: .public)")
    } else {
      logger.warning("Running with an in-memory Core Data fallback store after persistent store load failure.")
    }
    return LoadOutcome(status: .inMemoryFallback, errorDescription: initialError.localizedDescription)
  }

  private static func attemptLoad(in container: NSPersistentCloudKitContainer) -> [NSError] {
    var errors: [NSError] = []
    for description in container.persistentStoreDescriptions {
      description.shouldAddStoreAsynchronously = false
    }
    container.loadPersistentStores { _, error in
      if let error = error as NSError? {
        errors.append(error)
      }
    }
    return errors
  }

  private static func configureInMemory(_ container: NSPersistentCloudKitContainer) {
    let description = NSPersistentStoreDescription()
    description.type = NSInMemoryStoreType
    description.url = URL(fileURLWithPath: "/dev/null")
    description.cloudKitContainerOptions = nil
    description.shouldAddStoreAsynchronously = false
    container.persistentStoreDescriptions = [description]
  }

  private static func removeLoadedStores(from container: NSPersistentCloudKitContainer) {
    let coordinator = container.persistentStoreCoordinator
    for store in coordinator.persistentStores {
      do {
        try coordinator.remove(store)
      } catch {
        logger.error("Failed to detach persistent store during recovery: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  static func isCorruptionError(_ error: NSError) -> Bool {
    let sqliteCorruptionCodes: Set = [11, 24, 26]
    if error.domain == NSCocoaErrorDomain, error.code == NSFileReadCorruptFileError {
      return true
    }
    if error.domain == NSSQLiteErrorDomain, sqliteCorruptionCodes.contains(error.code) {
      return true
    }
    if let sqliteCode = error.userInfo[NSSQLiteErrorDomain] as? Int, sqliteCorruptionCodes.contains(sqliteCode) {
      return true
    }
    if let sqliteCode = error.userInfo[NSSQLiteErrorDomain] as? NSNumber, sqliteCorruptionCodes.contains(sqliteCode.intValue) {
      return true
    }
    if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError, isCorruptionError(underlying) {
      return true
    }
    if let detailed = error.userInfo[NSDetailedErrorsKey] as? [NSError], detailed.contains(where: isCorruptionError) {
      return true
    }
    return false
  }

  private static func recreateStoreFiles(for descriptions: [NSPersistentStoreDescription]) -> Bool {
    let fileManager = FileManager.default
    var removedAny = false

    for description in descriptions {
      guard let url = description.url, url.isFileURL, url.path != "/dev/null" else { continue }
      let sidecarURLs = [
        url,
        URL(fileURLWithPath: url.path + "-wal"),
        URL(fileURLWithPath: url.path + "-shm"),
        URL(fileURLWithPath: url.path + "-journal"),
      ]
      for fileURL in sidecarURLs where fileManager.fileExists(atPath: fileURL.path) {
        do {
          try fileManager.removeItem(at: fileURL)
          removedAny = true
        } catch {
          logger.error("Failed to remove corrupted store file \(fileURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
          return false
        }
      }
    }

    return removedAny
  }
}

public extension NSManagedObjectContext {
  func executeAndMergeChanges(_ batchDeleteRequest: NSBatchDeleteRequest) throws {
    batchDeleteRequest.resultType = .resultTypeObjectIDs
    let result = try execute(batchDeleteRequest) as? NSBatchDeleteResult
    let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: result?.result as? [NSManagedObjectID] ?? []]
    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self])
  }
}
