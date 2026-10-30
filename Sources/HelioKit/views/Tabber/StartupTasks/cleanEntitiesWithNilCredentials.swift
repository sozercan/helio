//
//  cleanEntitiesWithNilCredentials.swift
//  Helio
//
//  Created by Igor Marcossi on 30/11/23.
//

import CoreData
import Foundation

func cleanCredentialOrphanEntities() {
  func clean(_ e: String) {
    let context = PersistenceController.shared.container.viewContext
    let predicates = RedditCredentialsManager.shared.credentials.map { NSPredicate(format: "helioCredentialID != %@", $0.id as CVarArg) }
    let fetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: e)
    fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
    do {
      _ = try context.performAndWait { try context.executeAndMergeChanges(deleteRequest) }
    } catch _ as NSError {}
  }
  PersistenceController.shared.container.viewContext.performAndWait {
    clean("CachedSub")
    clean("CachedMulti")
  }
}
