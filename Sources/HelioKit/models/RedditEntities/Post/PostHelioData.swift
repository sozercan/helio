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
  var layoutWidth: Double = 0
  var layoutWindowHeight: Double = 0
  var layoutSecondary = false
  var layoutCompact: Bool?
  var layoutDynamicTypeSize: DynamicTypeSize?
  var layoutTitleStyle: PostLinkTheme.TitleStyle?
  var titleAttr: NSAttributedString?
  @ObservationIgnored var pageLayout: PostPageLayout?
  @ObservationIgnored var fetchesLinkMetadata = true
  @ObservationIgnored var deferredMedia: (() -> Void)?
  @ObservationIgnored var deferredMediaShown = false
  var linkMedia: PreviewModel?
  var videoMedia: SharedVideo?
  var postBodyAttr: NSAttributedString?
  var seenCommentsCount: Int?
  var seenComments: String?

  func resolveDeferredMedia() {
    deferredMediaShown = true
    let resolve = deferredMedia
    deferredMedia = nil
    resolve?()
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(permaURL)
    hasher.combine(subreddit)
    hasher.combine(postDimensions)
    hasher.combine(titleAttr)
    hasher.combine(postBodyAttr)
  }
}
