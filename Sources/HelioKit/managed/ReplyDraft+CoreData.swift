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
