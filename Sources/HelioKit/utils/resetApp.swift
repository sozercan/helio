import CoreData
import Defaults
import Foundation
import KeychainAccess

func resetPreferences() {
  UserDefaults.standard.removeAll()
}

func resetCaches() {
  Caches.streamable.removeAll()
}

func resetCoreData(keeping: Set<String> = []) {
  let container = PersistenceController.shared.container
  let entities = container.managedObjectModel.entities
  for entity in entities where !keeping.contains(entity.name ?? "") {
    delete(entityName: entity.name!)
  }

  func delete(entityName: String) {
    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
    let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
    do {
      _ = try container.viewContext.performAndWait {
        try container.viewContext.executeAndMergeChanges(deleteRequest)
      }
    } catch let error as NSError {
      debugPrint(error)
    }
  }
}

func clearReadHistory() {
  resetCoreData(keeping: Set(PersistenceController.shared.container.managedObjectModel.entities.compactMap(\.name)).subtracting(["SeenPost"]))
}
