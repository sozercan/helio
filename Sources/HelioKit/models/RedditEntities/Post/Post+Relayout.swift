//
//  Post+Relayout.swift
//  Helio
//

import Defaults
import SwiftUI

extension MediaExtractedType {
  /// Image requests are sized for the column; link previews, videos and embeds aren't, and
  /// extracting a link again would fetch its preview again. Reposts are laid out in place, and
  /// YouTube thumbnails requested again (see `relayoutingParts`).
  var dependsOnWidth: Bool {
    if case .imgs = self {
      true
    } else {
      false
    }
  }

  /// Extraction differs between compact and large rows only for images (thumbnail requests)
  /// and link previews. Others, like a Streamable video resolved after extraction, are kept.
  var dependsOnCompact: Bool {
    switch self {
    case .imgs, .link: true
    default: false
    }
  }

  /// The width-dependent part of media that's kept across a relayout: a YouTube embed's
  /// thumbnail request. Keeps its player.
  func relayoutingParts(contentWidth: Double, theme: HelioTheme) -> MediaExtractedType {
    guard case let .yt(yt) = self else { return self }
    return .yt(YTMediaExtracted(videoID: yt.videoID, size: yt.size, thumbnailURL: yt.thumbnailURL, thumbnailRequest: youTubeThumbnailRequest(yt.thumbnailURL, contentWidth: contentWidth, theme: theme), player: yt.player, author: yt.author, authorURL: yt.authorURL))
  }
}

extension Post {
  /// Recomputes media requests and row sizes for a new column width, window height (window
  /// resized, iPhone Duo folded or unfolded), presentation or compact mode. Does nothing if the
  /// post was already laid out for all four.
  func relayout(contentWidth: Double, theme: HelioTheme, secondary: Bool = false) {
    guard let helioData, let data, contentWidth > 0 else { return }
    let windowHeight = Double.screenH
    let sub = helioData.subreddit
    let compact = Post.isCompact(data, sub: sub)
    let compactChanged = helioData.layoutCompact != compact
    guard helioData.layoutWidth != contentWidth || helioData.layoutWindowHeight != windowHeight || helioData.layoutSecondary != secondary || compactChanged else { return }
    // Compact and large rows extract images and link previews differently, so a compact
    // change extracts those again.
    if (compactChanged && helioData.extractedMedia?.dependsOnCompact == true) || helioData.extractedMedia?.dependsOnWidth == true {
      helioData.extractedMedia = mediaExtractor(compact: compact, contentWidth: contentWidth, data, theme: theme)
    } else {
      helioData.extractedMedia = helioData.extractedMedia?.relayoutingParts(contentWidth: contentWidth, theme: theme)
    }
    if helioData.extractedMediaForcedNormal?.dependsOnWidth == true {
      helioData.extractedMediaForcedNormal = mediaExtractor(compact: false, contentWidth: contentWidth, data, theme: theme)
    } else {
      helioData.extractedMediaForcedNormal = helioData.extractedMediaForcedNormal?.relayoutingParts(contentWidth: contentWidth, theme: theme)
    }
    // Extracting a repost again would build a new embedded post, losing its votes and
    // previews, so lay the existing one out instead.
    for media in [helioData.extractedMedia, helioData.extractedMediaForcedNormal] {
      if case let .repost(embedded) = media {
        embedded.relayout(contentWidth: contentWidth, theme: theme, secondary: true)
      }
    }
    helioData.postDimensions = getPostDimensions(post: self, helioData: helioData, columnWidth: contentWidth, secondary: secondary, rawTheme: theme, subId: sub?.id)
    helioData.postDimensionsForcedNormal = getPostDimensions(post: self, helioData: helioData, columnWidth: contentWidth, secondary: secondary, rawTheme: theme, compact: false)
    helioData.layoutWidth = contentWidth
    helioData.layoutWindowHeight = windowHeight
    helioData.layoutSecondary = secondary
    helioData.layoutCompact = compact
  }
}

extension View {
  /// Re-lays out `posts` when the column width or window height changes (media height is
  /// capped by the window's), after it has settled: resizing a Mac window changes it every frame.
  /// Also when compact mode is switched, which changes every row's size.
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

  func body(content: Content) -> some View {
    content
      .task(id: [contentWidth, Double.screenH]) {
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        posts().forEach { $0.relayout(contentWidth: contentWidth, theme: theme) }
      }
      // Posts can be set up for another width after it settled: feeds fetch with the width they
      // were created with.
      .onChange(of: posts().map { $0.helioData?.layoutWidth ?? 0 }) {
        posts().forEach { $0.relayout(contentWidth: contentWidth, theme: theme) }
      }
      .onChange(of: feedDefSettings.compactPerSubreddit) {
        withAnimation { posts().forEach { $0.relayout(contentWidth: contentWidth, theme: theme) } }
      }
      .onChange(of: postLinkDefSettings.compactMode.enabled) {
        withAnimation { posts().forEach { $0.relayout(contentWidth: contentWidth, theme: theme) } }
      }
  }
}
