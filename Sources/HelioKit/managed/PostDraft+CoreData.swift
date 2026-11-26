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
