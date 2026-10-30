//
//  ReplyDraft+CoreData.swift
//  Helio
//
//  Written out by hand (codegen: Manual/None) because the model is compiled into the app
//  bundle while the code lives in the HelioKit package.
//

import CoreData
import Foundation

@objc(ReplyDraft)
public class ReplyDraft: NSManagedObject {}

public extension ReplyDraft {
  @nonobjc class func fetchRequest() -> NSFetchRequest<ReplyDraft> {
    NSFetchRequest<ReplyDraft>(entityName: "ReplyDraft")
  }

  @NSManaged var commentID: String?
  @NSManaged var replyText: String?
  @NSManaged var thingID: String?
  @NSManaged var timestamp: Date?
}
