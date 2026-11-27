import CoreData
import Foundation

@objc(SeenPost)
public class SeenPost: NSManagedObject {}

public extension SeenPost {
  @nonobjc class func fetchRequest() -> NSFetchRequest<SeenPost> {
    NSFetchRequest<SeenPost>(entityName: "SeenPost")
  }

  @NSManaged var numComments: Int32
  @NSManaged var postID: String?
  @NSManaged var seenComments: String?
}
