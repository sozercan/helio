//
//  SeenPost+CoreData.swift
//  Helio
//
//  Written out by hand (codegen: Manual/None) because the model is compiled into the app
//  bundle while the code lives in the HelioKit package.
//

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
