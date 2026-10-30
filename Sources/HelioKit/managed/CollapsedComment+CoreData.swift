//
//  CollapsedComment+CoreData.swift
//  Helio
//
//  Written out by hand (codegen: Manual/None) because the model is compiled into the app
//  bundle while the code lives in the HelioKit package.
//

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
