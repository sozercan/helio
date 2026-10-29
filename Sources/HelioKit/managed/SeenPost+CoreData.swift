//
//  SeenPost+CoreData.swift
//  Helio
//
//  Written out by hand (codegen: Manual/None) because the model is compiled into the app
//  bundle while the code lives in the HelioKit package.
//

import Foundation
import CoreData

@objc(SeenPost)
public class SeenPost: NSManagedObject {}

extension SeenPost {
  @nonobjc public class func fetchRequest() -> NSFetchRequest<SeenPost> {
    NSFetchRequest<SeenPost>(entityName: "SeenPost")
  }

  @NSManaged public var numComments: Int32
  @NSManaged public var postID: String?
  @NSManaged public var seenComments: String?
}
