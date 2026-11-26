import CoreData

struct PersistenceController {
  static let shared = PersistenceController()

  let container: NSPersistentCloudKitContainer
  let primaryBGContext: NSManagedObjectContext
  let accountListsContext: NSManagedObjectContext

  init(inMemory: Bool = false) {
    container = NSPersistentCloudKitContainer(name: "Helio")

    if inMemory {
      container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
    }

    container.loadPersistentStores(completionHandler: { _, error in
      if let error = error as NSError? {
        fatalError("Unresolved error \(error), \(error.userInfo)")
      }
    })

    accountListsContext = container.newBackgroundContext()
    accountListsContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    accountListsContext.automaticallyMergesChangesFromParent = true

    self.primaryBGContext = container.newBackgroundContext()
    self.primaryBGContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    self.primaryBGContext.automaticallyMergesChangesFromParent = true
    container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    container.viewContext.automaticallyMergesChangesFromParent = true
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
