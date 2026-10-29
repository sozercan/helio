//
//  PostDraft+CoreData.swift
//  Helio
//
//  Written out by hand (codegen: Manual/None) because the model is compiled into the app
//  bundle while the code lives in the HelioKit package.
//

import Foundation
import CoreData

@objc(PostDraft)
public class PostDraft: NSManagedObject {}

extension PostDraft {
  @nonobjc public class func fetchRequest() -> NSFetchRequest<PostDraft> {
    NSFetchRequest<PostDraft>(entityName: "PostDraft")
  }

  @NSManaged public var flairID: String?
  @NSManaged public var flairText: String?
  @NSManaged public var subredditName: String?
  @NSManaged public var text: String?
  @NSManaged public var timestamp: Date?
  @NSManaged public var title: String?
  @NSManaged public var url: String?
  @NSManaged public var uuid: UUID?
}
