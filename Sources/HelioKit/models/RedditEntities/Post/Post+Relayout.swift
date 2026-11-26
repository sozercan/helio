import Defaults
import SwiftUI
import YouTubePlayerKit

extension MediaExtractedType {
  var dependsOnWidth: Bool {
    if case .imgs = self {
      true
    } else {
      false
    }
  }

  var dependsOnCompact: Bool {
    switch self {
    case .imgs, .link: true
    default: false
    }
  }

  func relayoutingParts(contentWidth: Double, theme: HelioTheme) -> MediaExtractedType {
    guard case let .yt(yt) = self else { return self }
    return .yt(YTMediaExtracted(videoID: yt.videoID, size: yt.size, thumbnailURL: yt.thumbnailURL, thumbnailRequest: youTubeThumbnailRequest(yt.thumbnailURL, contentWidth: contentWidth, theme: theme), player: yt.player, author: yt.author, authorURL: yt.authorURL))
  }
}

extension Post {
  func relayout(contentWidth: Double, theme: HelioTheme, secondary: Bool = false) {
    guard let helioData, let data, contentWidth > 0 else { return }
    let windowHeight = Double.screenH
    let textSize = ContentTextScale.dynamicTypeSize
    let sub = helioData.subreddit
    let compact = Post.isCompact(data, sub: sub)
    let compactChanged = helioData.layoutCompact != compact
    let mediaChanged = helioData.layoutWidth != contentWidth || helioData.layoutWindowHeight != windowHeight || helioData.layoutSecondary != secondary || compactChanged
    let titleText = theme.postLinks.theme.titleText
    let titleStyle = theme.postLinks.theme.titleStyle
    let titleChanged = helioData.layoutDynamicTypeSize != textSize || helioData.layoutTitleStyle != titleStyle
    guard mediaChanged || titleChanged else { return }
    if mediaChanged {
      if (compactChanged && helioData.extractedMedia?.dependsOnCompact == true) || helioData.extractedMedia?.dependsOnWidth == true {
        helioData.extractedMedia = mediaExtractor(compact: compact, contentWidth: contentWidth, data, theme: theme, fetchLinkMetadata: helioData.fetchesLinkMetadata)
      } else {
        helioData.extractedMedia = helioData.extractedMedia?.relayoutingParts(contentWidth: contentWidth, theme: theme)
      }
      if helioData.extractedMediaForcedNormal?.dependsOnWidth == true {
        helioData.extractedMediaForcedNormal = mediaExtractor(compact: false, contentWidth: contentWidth, data, theme: theme, fetchLinkMetadata: helioData.fetchesLinkMetadata)
      } else {
        helioData.extractedMediaForcedNormal = helioData.extractedMediaForcedNormal?.relayoutingParts(contentWidth: contentWidth, theme: theme)
      }
    }
    for media in [helioData.extractedMedia, helioData.extractedMediaForcedNormal] {
      if case let .repost(embedded) = media {
        embedded.relayout(contentWidth: contentWidth, theme: theme, secondary: true)
      }
    }
    if titleChanged {
      helioData.titleAttr = createTitleTagsAttrString(titleTheme: titleText, postData: data, textColor: titleText.color.uiColor(), uncoloredFlair: titleStyle.flair, dynamicTypeSize: textSize)
    }
    helioData.postDimensions = getPostDimensions(post: self, helioData: helioData, columnWidth: contentWidth, secondary: secondary, rawTheme: theme, subId: sub?.settingsKey, dynamicTypeSize: textSize)
    helioData.postDimensionsForcedNormal = getPostDimensions(post: self, helioData: helioData, columnWidth: contentWidth, secondary: secondary, rawTheme: theme, compact: false, dynamicTypeSize: textSize)
    helioData.layoutWidth = contentWidth
    helioData.layoutWindowHeight = windowHeight
    helioData.layoutSecondary = secondary
    helioData.layoutCompact = compact
    helioData.layoutDynamicTypeSize = textSize
    helioData.layoutTitleStyle = titleStyle
  }
}

struct PostPageLayout {
  struct Key: Equatable {
    let width: Double
    let windowHeight: Double
    let theme: HelioTheme
    let source: MediaExtractedType?
  }

  let key: Key
  let media: MediaExtractedType?
  let mediaSize: CGSize?
}

extension Post {
  func pageLayout(contentWidth: Double, theme: HelioTheme) -> PostPageLayout? {
    guard let helioData, let data, contentWidth > 0 else { return nil }
    let source = helioData.extractedMediaForcedNormal
    let key = PostPageLayout.Key(width: contentWidth, windowHeight: .screenH, theme: theme, source: source)
    if let layout = helioData.pageLayout, layout.key == key {
      return layout
    }
    let media = source?.dependsOnWidth == true ? mediaExtractor(compact: false, contentWidth: contentWidth, data, theme: theme) : source?.relayoutingParts(contentWidth: contentWidth, theme: theme)
    let dimensions = getPostDimensions(post: self, helioData: helioData, columnWidth: contentWidth, rawTheme: theme, compact: false)
    let layout = PostPageLayout(key: key, media: media, mediaSize: dimensions.mediaSize)
    helioData.pageLayout = layout
    return layout
  }
}

@MainActor
final class PageYouTubePlayer {
  private var current: (videoID: String, player: YouTubePlayer)?

  func owning(_ media: MediaExtractedType) -> MediaExtractedType {
    guard case let .yt(yt) = media else { return media }
    if current?.videoID != yt.videoID {
      current = (yt.videoID, YouTubePlayer(source: .video(id: yt.videoID)))
    }
    guard let player = current?.player else { return media }
    return .yt(YTMediaExtracted(videoID: yt.videoID, size: yt.size, thumbnailURL: yt.thumbnailURL, thumbnailRequest: yt.thumbnailRequest, player: player, author: yt.author, authorURL: yt.authorURL))
  }
}

extension View {
  func relayoutPosts(_ posts: @escaping () -> [Post], contentWidth: Double, theme: HelioTheme) -> some View {
    modifier(RelayoutPostsModifier(posts: posts, contentWidth: contentWidth, theme: theme))
  }
}

private struct RelayoutPostsModifier: ViewModifier {
  let posts: () -> [Post]
  let contentWidth: Double
  let theme: HelioTheme

  @Default(.SubredditFeedDefSettings) private var feedDefSettings
  @Default(.PostLinkDefSettings) private var postLinkDefSettings
  @Environment(\.contentTypeSize) private var dynamicTypeSize

  func body(content: Content) -> some View {
    content
      .onChange(of: dynamicTypeSize) { _, size in
        ContentTextScale.dynamicTypeSize = size
        posts().forEach { $0.relayout(contentWidth: contentWidth, theme: theme) }
      }
      .task(id: [contentWidth, Double.screenH]) {
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        posts().forEach { $0.relayout(contentWidth: contentWidth, theme: theme) }
      }
      .onChange(of: posts().map { $0.helioData?.layoutWidth ?? 0 }) {
        posts().forEach { $0.relayout(contentWidth: contentWidth, theme: theme) }
      }
      .onChange(of: feedDefSettings.compactPerSubreddit) {
        withAnimation { posts().forEach { $0.relayout(contentWidth: contentWidth, theme: theme) } }
      }
      .onChange(of: postLinkDefSettings.compactMode.enabled) {
        withAnimation { posts().forEach { $0.relayout(contentWidth: contentWidth, theme: theme) } }
      }
      .onChange(of: theme.postLinks.theme.titleStyle) {
        posts().forEach { $0.relayout(contentWidth: contentWidth, theme: theme) }
      }
  }
}
