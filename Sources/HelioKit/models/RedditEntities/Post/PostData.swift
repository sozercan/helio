//
//  PostData.swift
//  Helio
//
//  Created by Igor Marcossi on 25/01/24.
//

import Foundation

struct PostData: GenericRedditEntityDataType {
  let subreddit: String
  var selftext: String?
  var author_fullname: String?
  var saved: Bool
  let gilded: Int
  let clicked: Bool
  let title: String
  let subreddit_name_prefixed: String
  let hidden: Bool
  var ups: Int
  var downs: Int
  let hide_score: Bool
  var post_hint: String?
  let name: String
  let quarantine: Bool
  var link_flair_text_color: String?
  let upvote_ratio: Double
  let subreddit_type: String
  let total_awards_received: Int
  let is_self: Bool
  let created: Double
  let domain: String
  let allow_live_comments: Bool
  var selftext_html: String?
  let id: String
  let is_robot_indexable: Bool
  let author: String
  let num_comments: Int
  let send_replies: Bool
  var whitelist_status: String?
  let contest_mode: Bool
  let permalink: String
  let url: String
  let subreddit_subscribers: Int
  var created_utc: Double?
  let num_crossposts: Int
  var is_video: Bool?
  var is_gallery: Bool?
  var gallery_data: GalleryData?
  var crosspost_parent_list: [PostData]?
  var media_metadata: [String: MediaMetadataItem?]?
  // Optional properties
  var wls: Int?
  var pwls: Int?
  var link_flair_text: String?
  var thumbnail: String?
  //  let edited: Edited?
  var link_flair_template_id: String?
  var author_flair_text: String?
  var media: Media?
  var approved_at_utc: Int?
  var mod_reason_title: String?
  var top_awarded_type: String?
  var author_flair_background_color: String?
  var approved_by: String?
  var is_created_from_ads_ui: Bool?
  var author_premium: Bool?
  var author_flair_css_class: String?
  var gildings: [String: Int]?
  var content_categories: [String]?
  var mod_note: String?
  var link_flair_type: String?
  var removed_by_category: String?
  var banned_by: String?
  var author_flair_type: String?
  var likes: Bool?
  var stickied: Bool?
  var suggested_sort: String?
  var banned_at_utc: String?
  var view_count: String?
  var archived: Bool?
  var no_follow: Bool?
  var is_crosspostable: Bool?
  var pinned: Bool?
  var over_18: Bool?
  //  let all_awardings: [Awarding]?
  var awarders: [String]?
  var media_only: Bool?
  var can_gild: Bool?
  var spoiler: Bool?
  var locked: Bool?
  var treatment_tags: [String]?
  var visited: Bool?
  var removed_by: String?
  var num_reports: Int?
  var distinguished: String?
  var subreddit_id: String?
  var author_is_blocked: Bool?
  var mod_reason_by: String?
  var removal_reason: String?
  var link_flair_background_color: String?
  var report_reasons: [String]?
  var discussion_type: String?
  var secure_media: Media?
  var secure_media_embed: SecureMediaEmbed?
  var preview: Preview?
  var helioSeen: Bool?
  var helioHidden: Bool?

  var badgeKit: BadgeKit {
    BadgeKit(
      numComments: num_comments,
      ups: ups,
      saved: saved,
      author: author,
      authorFullname: author_fullname ?? "",
      userFlair: author_flair_text ?? "",
      created: created,
    )
  }

  var votesKit: VotesKit {
    VotesKit(ups: ups, ratio: upvote_ratio, likes: likes, id: id)
  }
}

struct GalleryData: Codable, Hashable {
  let items: [GalleryDataItem]?
}

struct GalleryDataItem: Codable, Hashable, Identifiable {
  let media_id: String
  let id: Double
}

struct MediaMetadataItem: Codable, Hashable, Identifiable {
  let status: String
  let e: String?
  let m: String?
  let p: [MediaMetadataItemSize]?
  let s: MediaMetadataItemSize?
  let id: String?
}

struct MediaMetadataItemSize: Codable, Hashable {
  let x: Int
  let y: Int
  let u: String?
}

struct PreviewImg: Codable, Hashable {
  let url: String?
  let width: Int?
  let height: Int?
  let id: String?
}

struct PreviewImgCollection: Codable, Hashable {
  let source: PreviewImg?
  let resolutions: [PreviewImg]?
  ///  let variants: Oembed?
  let id: String?
}

struct RedditVideoPreview: Codable, Hashable {
  let bitrate_kbps: Double?
  let fallback_url: String?
  let height: Double?
  let width: Double?
  let scrubber_media_url: String?
  let dash_url: String?
  let duration: Double?
  let hls_url: String?
  let is_gif: Bool?
  let transcoding_status: String?
}

struct Preview: Codable, Hashable {
  let images: [PreviewImgCollection]?
  let reddit_video_preview: RedditVideoPreview?
  let enabled: Bool?
}

struct Media: Codable, Hashable {
  let type: String?
  let oembed: Oembed?
  let reddit_video: RedditVideo?
}

struct Oembed: Codable, Hashable {
  let provider_url: String?
  let version: String?
  let title: String?
  let type: String?
  let thumbnail_width: Int?
  let height: Int?
  let width: Int?
  let html: String?
  let author_name: String?
  let provider_name: String?
  let thumbnail_url: String?
  let thumbnail_height: Int?
  let author_url: String?
}

struct RedditVideo: Codable, Hashable {
  let bitrate_kbps: Int?
  let fallback_url: String?
  let has_audio: Bool?
  let height: Int?
  let width: Int?
  let scrubber_media_url: String?
  let dash_url: String?
  let duration: Int?
  let hls_url: String?
  let is_gif: Bool?
  let transcoding_status: String?
}

struct SecureMediaEmbed: Codable, Hashable {
  let content: String?
  let width: Int?
  let scrolling: Bool?
  let media_domain_url: String?
  let height: Int?
}
