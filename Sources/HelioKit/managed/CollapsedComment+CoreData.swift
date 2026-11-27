import CoreData
import Foundation

@objc(CollapsedComment)
public class CollapsedComment: NSManagedObject {}

public extension CollapsedComment {
  @nonobjc class func fetchRequest() -> NSFetchRequest<CollapsedComment> {
    NSFetchRequest<CollapsedComment>(entityName: "CollapsedComment")
  }

  @NSManaged var commentID: String?
}
