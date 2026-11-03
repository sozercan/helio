//
//  PostHelioData.swift
//  Helio
//
//  Created by Igor Marcossi on 26/01/24.
//

import Nuke
import SwiftUI

@Observable
class PostHelioData: Hashable {
  static func == (lhs: PostHelioData, rhs: PostHelioData) -> Bool {
    lhs.permaURL == rhs.permaURL
  }

  var permaURL: URL?
  var extractedMedia: MediaExtractedType?
  var extractedMediaForcedNormal: MediaExtractedType?
  var _strongSubreddit: Subreddit?
  weak var _weakSubreddit: Subreddit?
  var subreddit: Subreddit? {
    get { _weakSubreddit ?? _strongSubreddit }
    set { _weakSubreddit = newValue }
  }

  var mediaImageRequest: [ImageRequest] = []
  var avatarImageRequest: ImageRequest?
  var postDimensions: PostDimensions = .zero
  var postDimensionsForcedNormal: PostDimensions = .zero
  /// The column width, window height and presentation (embedded or not) the dimensions were
  /// computed for.
  var layoutWidth: Double = 0
  var layoutWindowHeight: Double = 0
  var layoutSecondary = false
  /// Whether the row was laid out as compact.
  var layoutCompact: Bool?
  /// The text size the title was drawn and measured for (see `ContentTextScale`).
  var layoutDynamicTypeSize: DynamicTypeSize?
  /// The theme's title style (text and uncolored flair) the title was drawn and measured in.
  var layoutTitleStyle: PostLinkTheme.TitleStyle?
  var titleAttr: NSAttributedString?
  /// The post page's layout, kept apart from the feed row's: side by side, the page and the row
  /// are in columns of different widths. Derived when the page draws (`Post.pageLayout`).
  @ObservationIgnored var pageLayout: PostPageLayout?
  /// Whether the post's link previews download their page as soon as they're extracted, or only
  /// once they show (`Post.fetchesLinkMetadata`).
  @ObservationIgnored var fetchesLinkMetadata = true
  /// Loads media the post didn't load when it was extracted, because it defers link metadata:
  /// a Streamable video, or the post, comment, user or subreddit it links to. Called when its
  /// media shows (`resolveDeferredMedia`).
  @ObservationIgnored var deferredMedia: (() -> Void)?
  /// Whether the post's deferred media has shown, as on its page: from then on, laying the post
  /// out again (refreshing it) loads its media right away, since it's on screen.
  @ObservationIgnored var deferredMediaShown = false
  var linkMedia: PreviewModel?
  var videoMedia: SharedVideo?
  var postBodyAttr: NSAttributedString?
  var seenCommentsCount: Int?
  var seenComments: String?

  /// Starts loading deferred media, once.
  func resolveDeferredMedia() {
    deferredMediaShown = true
    let resolve = deferredMedia
    deferredMedia = nil
    resolve?()
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(permaURL)
    //    hasher.combine(extractedMedia)
    hasher.combine(subreddit)
    hasher.combine(postDimensions)
    hasher.combine(titleAttr)
    hasher.combine(postBodyAttr)
  }
}
