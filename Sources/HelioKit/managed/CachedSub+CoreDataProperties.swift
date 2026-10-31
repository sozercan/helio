//
//  CachedSub+CoreDataProperties.swift
//  Helio
//
//  Created by Igor Marcossi on 25/08/23.
//
//

import CoreData
import Foundation

public extension CachedSub {
  @nonobjc class func fetchRequest() -> NSFetchRequest<CachedSub> {
    NSFetchRequest<CachedSub>(entityName: "CachedSub")
  }

  @NSManaged var allow_galleries: Bool
  @NSManaged var allow_images: Bool
  @NSManaged var allow_videos: Bool
  @NSManaged var banner_background_color: String?
  @NSManaged var banner_background_image: String?
  @NSManaged var banner_img: String?
  @NSManaged var community_icon: String?
  @NSManaged var display_name: String?
  @NSManaged var header_img: String?
  @NSManaged var icon_img: String?
  @NSManaged var key_color: String?
  @NSManaged var name: String?
  @NSManaged var over18: Bool
  @NSManaged var primary_color: String?
  @NSManaged var restrict_commenting: Bool
  @NSManaged var subscribers: Double
  @NSManaged var title: String?
  @NSManaged var url: String?
  @NSManaged var user_flair_background_color: String?
  @NSManaged var user_has_favorited: Bool
  @NSManaged var user_is_banned: Bool
  @NSManaged var user_is_moderator: Bool
  @NSManaged var user_is_subscriber: Bool
  @NSManaged var uuid: String?
  @NSManaged var helioCredentialID: UUID?
  @NSManaged var multis: Set<CachedMulti>?

  internal convenience init(data: SubredditData, context: NSManagedObjectContext, credentialID: UUID) {
    self.init(context: context)
    update(data: data, credentialID: credentialID)
  }

  internal func update(data x: SubredditData, credentialID: UUID) {
    self.uuid = x.name
    self.allow_galleries = x.allow_galleries ?? false
    self.allow_images = x.allow_images ?? false
    self.allow_videos = x.allow_videos ?? false
    self.over18 = x.over18 ?? false
    self.restrict_commenting = x.restrict_commenting ?? false
    self.user_has_favorited = x.user_has_favorited ?? false
    self.user_is_banned = x.user_is_banned ?? false
    self.user_is_moderator = x.user_is_moderator ?? false
    self.user_is_subscriber = x.user_is_subscriber ?? false
    self.banner_background_color = x.banner_background_color
    self.banner_background_image = x.banner_background_image
    self.banner_img = x.banner_img
    self.community_icon = x.community_icon
    self.display_name = x.display_name
    self.header_img = x.header_img
    self.icon_img = x.icon_img
    self.key_color = x.key_color
    self.name = x.name
    self.primary_color = x.primary_color
    self.title = x.title
    self.url = x.url
    self.user_flair_background_color = x.user_flair_background_color
    self.subscribers = Double(x.subscribers ?? 0)
    self.helioCredentialID = credentialID
  }
}

extension CachedSub: Identifiable {}
