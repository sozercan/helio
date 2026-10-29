//
//  ReplyDraft+CoreData.swift
//  Helio
//
//  Written out by hand (codegen: Manual/None) because the model is compiled into the app
//  bundle while the code lives in the HelioKit package.
//

import Foundation
import CoreData

@objc(ReplyDraft)
public class ReplyDraft: NSManagedObject {}

extension ReplyDraft {
  @nonobjc public class func fetchRequest() -> NSFetchRequest<ReplyDraft> {
    NSFetchRequest<ReplyDraft>(entityName: "ReplyDraft")
  }

  @NSManaged public var commentID: String?
  @NSManaged public var replyText: String?
  @NSManaged public var thingID: String?
  @NSManaged public var timestamp: Date?
}
