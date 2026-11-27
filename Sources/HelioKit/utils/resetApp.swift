import CoreData
import Defaults
import Foundation
import KeychainAccess

func resetPreferences() {
  UserDefaults.standard.removeAll()
  UserCollectionsStore.shared.resetAll()
}

func resetCaches() {
  Caches.postsAttrStr.cache.removeAll()
  Caches.videos.cache.removeAll()
}

func resetCoreData(keeping: Set<String> = [], container: NSPersistentContainer = PersistenceController.shared.container) {
  let entities = container.managedObjectModel.entities
  let usesSQLite = container.persistentStoreCoordinator.persistentStores.allSatisfy { $0.type == NSSQLiteStoreType }
  for entity in entities where !keeping.contains(entity.name ?? "") {
    if let name = entity.name {
      delete(entityName: name)
    }
  }

  func delete(entityName: String) {
    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
    if usesSQLite {
      let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
      do {
        _ = try container.viewContext.performAndWait {
          try container.viewContext.executeAndMergeChanges(deleteRequest)
        }
      } catch let error as NSError {
        debugPrint(error)
      }
    } else {
      container.viewContext.performAndWait {
        do {
          if let objects = try container.viewContext.fetch(fetchRequest) as? [NSManagedObject] {
            for object in objects {
              container.viewContext.delete(object)
            }
            if container.viewContext.hasChanges {
              try container.viewContext.save()
            }
          }
        } catch let error as NSError {
          debugPrint(error)
        }
      }
    }
  }
}

func clearReadHistory() {
  resetCoreData(keeping: Set(PersistenceController.shared.container.managedObjectModel.entities.compactMap(\.name)).subtracting(["SeenPost"]))
}
