//
//  resetApp.swift
//  Helio
//
//  Created by Igor Marcossi on 04/09/23.
//

import Foundation
import Defaults
import KeychainAccess
import CoreData

func resetApp() {
  resetCaches()
  resetCoreData()
  resetPreferences()
  resetCredentials()
}

func resetCredentials() {
  RedditCredentialsManager.shared.credentials.forEach { $0.delete() }
  
  let credentialsKeychain = Keychain(service: "net.phfactor.winston.reddit-credentials").synchronizable(Defaults[.BehaviorDefSettings].iCloudSyncCredentials)
  
  credentialsKeychain["apiAppID"] = nil
  credentialsKeychain["apiAppSecret"] = nil
  credentialsKeychain["accessToken"] = nil
  credentialsKeychain["refreshToken"] = nil
}

func resetPreferences() {
  UserDefaults.standard.removeAll()
}

func resetCaches() {
  Caches.postsAttrStr.cache.removeAll()
  Caches.videos.cache.removeAll()
}

/// - Parameter keeping: entity names to leave untouched.
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
//        try container.viewContext.save()
      }
    } catch let error as NSError {
      debugPrint(error)
    }
  }
}

/// Forgets which posts have been read.
func clearReadHistory() {
  resetCoreData(keeping: Set(PersistenceController.shared.container.managedObjectModel.entities.compactMap(\.name)).subtracting(["SeenPost"]))
}
