//
//  PostDraft+CoreData.swift
//  Helio
//
//  Written out by hand (codegen: Manual/None) because the model is compiled into the app
//  bundle while the code lives in the HelioKit package.
//

import CoreData
import Foundation

@objc(PostDraft)
public class PostDraft: NSManagedObject {}

public extension PostDraft {
  @nonobjc class func fetchRequest() -> NSFetchRequest<PostDraft> {
    NSFetchRequest<PostDraft>(entityName: "PostDraft")
  }

  @NSManaged var flairID: String?
  @NSManaged var flairText: String?
  @NSManaged var subredditName: String?
  @NSManaged var text: String?
  @NSManaged var timestamp: Date?
  @NSManaged var title: String?
  @NSManaged var url: String?
  @NSManaged var uuid: UUID?
}
