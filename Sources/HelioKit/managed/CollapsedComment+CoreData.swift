//
//  CollapsedComment+CoreData.swift
//  Helio
//
//  Written out by hand (codegen: Manual/None) because the model is compiled into the app
//  bundle while the code lives in the HelioKit package.
//

import Foundation
import CoreData

@objc(CollapsedComment)
public class CollapsedComment: NSManagedObject {}

extension CollapsedComment {
  @nonobjc public class func fetchRequest() -> NSFetchRequest<CollapsedComment> {
    NSFetchRequest<CollapsedComment>(entityName: "CollapsedComment")
  }

  @NSManaged public var commentID: String?
}
