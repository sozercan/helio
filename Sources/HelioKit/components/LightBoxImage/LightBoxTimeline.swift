//
//  LightBoxTimeline.swift
//  Helio
//

import NukeUI
import SwiftUI

/// The post a lightbox image is from, for the title and author shown over it.
struct LightBoxPost {
  /// Tells the posts apart, so paging within a gallery doesn't mark its post read again.
  var key: String
  var title: String?
  var badgeKit: BadgeKit?
  var avatarImageRequest: ImageRequest?
  /// Marks the post read once its image shows, when "Read on preview media" is on.
  var markAsSeen: (() async -> Void)?

  /// A page for each of the post's images.
  func pages(_ images: [ImgExtracted]) -> [LightBoxPage] {
    images.enumerated().map { LightBoxPage(img: $1, post: self, index: $0, count: images.count) }
  }
}

/// One image in the lightbox.
struct LightBoxPage {
  var img: ImgExtracted
  var post: LightBoxPost
  /// The image's place among its post's images.
  var index: Int
  var count: Int
}

/// What the lightbox shows: its pages, and the one it opens on.
struct LightBoxTimeline: Identifiable {
  let id = UUID()
  var pages: [LightBoxPage]
  var start: Int

  /// The images of the post opened, between those of the image posts around it in the feed, so a
  /// swipe goes on to the next or previous post's. Outside a feed, or for a post the feed doesn't
  /// list (a crosspost's original), just the post's own images.
  @MainActor
  static func around(_ helioData: PostHelioData?, in feed: (any FeedPostsSource)?, own: [LightBoxPage], start: Int) -> LightBoxTimeline {
    guard let helioData, let posts = feed?.feedPosts, posts.contains(where: { $0.helioData === helioData }) else {
      return LightBoxTimeline(pages: own, start: start)
    }
    let settings = CachedDefaults[.PostLinkDefSettings]
    var pages: [LightBoxPage] = []
    var startPage = start
    for post in posts {
      if post.helioData === helioData {
        startPage = pages.count + start
        pages += own
        continue
      }
      guard let data = post.data, let postHelioData = post.helioData, case let .imgs(images) = postHelioData.extractedMedia, !images.isEmpty else { continue }
      // A blurred NSFW post's image shows only when it's opened by itself.
      if settings.blurNSFW, data.over_18 ?? false {
        continue
      }
      let markAsSeen: (() async -> Void)? = settings.lightboxReadsPost ? { await post.toggleSeen(true) } : nil
      pages += LightBoxPost(key: post.id, title: data.title, badgeKit: data.badgeKit, avatarImageRequest: postHelioData.avatarImageRequest, markAsSeen: markAsSeen).pages(images)
    }
    return LightBoxTimeline(pages: pages, start: startPage)
  }
}

/// A feed's posts in order, for the lightbox to page on through their images.
@MainActor
protocol FeedPostsSource: AnyObject {
  var feedPosts: [Post] { get }
}

extension FeedItemsManager: FeedPostsSource {
  var feedPosts: [Post] {
    entities.compactMap {
      if case let .post(post) = $0 {
        post
      } else {
        nil
      }
    }
  }
}

extension EnvironmentValues {
  /// The feed a post row is in, set by the feed on its rows.
  @Entry var feedPostsSource: (any FeedPostsSource)?
}
