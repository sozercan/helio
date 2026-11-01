//
//  CachedMulti+CoreDataProperties.swift
//  Helio
//
//  Created by Igor Marcossi on 25/08/23.
//
//

import CoreData
import Foundation

public extension CachedMulti {
  @nonobjc class func fetchRequest() -> NSFetchRequest<CachedMulti> {
    NSFetchRequest<CachedMulti>(entityName: "CachedMulti")
  }

  @NSManaged var display_name: String?
  @NSManaged var icon_url: String?
  @NSManaged var key_color: String?
  @NSManaged var name: String?
  @NSManaged var over_18: Bool
  @NSManaged var path: String?
  @NSManaged var uuid: String?
  @NSManaged var subreddits: Set<CachedSub>?
  @NSManaged var helioCredentialID: UUID?

  internal convenience init(data: MultiData, context: NSManagedObjectContext, credentialID: UUID) {
    self.init(context: context)
    update(data, credentialID: credentialID)
  }

  var subsArray: [CachedSub] {
    let set = subreddits ?? []
    return set.sorted {
      $0.display_name ?? "" < $1.display_name ?? ""
    }
  }

  internal func getSubEntities(_ subs: [MultiSub], context: NSManagedObjectContext, credentialID: UUID) -> [CachedSub] {
    var cachedSubs: [String: CachedSub] = [:]
    let fetchRequest = NSFetchRequest<CachedSub>(entityName: "CachedSub")
    fetchRequest.predicate = NSPredicate(format: "helioCredentialID == %@", credentialID as CVarArg)
    if let results = (context.performAndWait { try? context.fetch(fetchRequest) }) {
      for cachedSub in results {
        context.performAndWait {
          if let name = cachedSub.name {
            cachedSubs[name] = cachedSub
          }
        }
      }
    }

    return subs.compactMap { subData in
      if let data = subData.data, let found = cachedSubs[data.name] {
        return found
      }
      if let y = subData.data {
        return CachedSub(data: y, context: context, credentialID: credentialID)
      }
      return nil
    }
  }

  internal func update(_ data: MultiData, credentialID: UUID) {
    guard let ctx = self.managedObjectContext else { return }
    let subs = getSubEntities(data.subreddits ?? [], context: ctx, credentialID: credentialID)
    self.display_name = data.display_name
    self.icon_url = data.icon_url ?? ""
    self.key_color = data.key_color ?? ""
    self.name = data.name
    self.over_18 = data.over_18 ?? false
    self.path = data.path
    self.uuid = data.id
    self.subreddits = Set(subs)
    self.helioCredentialID = credentialID
  }
}

// MARK: Generated accessors for subreddits

public extension CachedMulti {
  @objc(addSubredditsObject:)
  @NSManaged func addToSubreddits(_ value: CachedSub)

  @objc(removeSubredditsObject:)
  @NSManaged func removeFromSubreddits(_ value: CachedSub)

  @objc(addSubreddits:)
  @NSManaged func addToSubreddits(_ values: NSSet)

  @objc(removeSubreddits:)
  @NSManaged func removeFromSubreddits(_ values: NSSet)
}

extension CachedMulti: Identifiable {}
