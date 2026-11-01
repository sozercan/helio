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
  var titleAttr: NSAttributedString?
  var linkMedia: PreviewModel?
  var videoMedia: SharedVideo?
  var postBodyAttr: NSAttributedString?
  var seenCommentsCount: Int?
  var seenComments: String?

  func hash(into hasher: inout Hasher) {
    hasher.combine(permaURL)
    //    hasher.combine(extractedMedia)
    hasher.combine(subreddit)
    hasher.combine(postDimensions)
    hasher.combine(titleAttr)
    hasher.combine(postBodyAttr)
  }
}
