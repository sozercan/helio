//
//  Post+Relayout.swift
//  winston
//

import SwiftUI

extension MediaExtractedType {
  /// Image requests are sized for the column; link previews, videos and embeds aren't, and
  /// extracting a link again would fetch its preview again. Reposts are laid out in place, and
  /// YouTube thumbnails requested again (see `relayoutingParts`).
  var dependsOnWidth: Bool {
    if case .imgs = self { true } else { false }
  }

  /// The width-dependent part of media that's kept across a relayout: a YouTube embed's
  /// thumbnail request. Keeps its player.
  func relayoutingParts(contentWidth: Double, theme: WinstonTheme) -> MediaExtractedType {
    guard case .yt(let yt) = self else { return self }
    return .yt(YTMediaExtracted(videoID: yt.videoID, size: yt.size, thumbnailURL: yt.thumbnailURL, thumbnailRequest: youTubeThumbnailRequest(yt.thumbnailURL, contentWidth: contentWidth, theme: theme), player: yt.player, author: yt.author, authorURL: yt.authorURL))
  }
}

extension Post {
  /// Recomputes media requests and row sizes for a new column width, window height (window
  /// resized, iPhone Duo folded or unfolded) or presentation. Does nothing if the post was
  /// already laid out for all three.
  func relayout(contentWidth: Double, theme: WinstonTheme, secondary: Bool = false) {
    guard let winstonData, let data, contentWidth > 0 else { return }
    let windowHeight = Double.screenH
    guard winstonData.layoutWidth != contentWidth || winstonData.layoutWindowHeight != windowHeight || winstonData.layoutSecondary != secondary else { return }
    let sub = winstonData.subreddit
    if winstonData.extractedMedia?.dependsOnWidth == true {
      winstonData.extractedMedia = mediaExtractor(compact: Post.isCompact(data, sub: sub), contentWidth: contentWidth, data, theme: theme)
    } else {
      winstonData.extractedMedia = winstonData.extractedMedia?.relayoutingParts(contentWidth: contentWidth, theme: theme)
    }
    if winstonData.extractedMediaForcedNormal?.dependsOnWidth == true {
      winstonData.extractedMediaForcedNormal = mediaExtractor(compact: false, contentWidth: contentWidth, data, theme: theme)
    } else {
      winstonData.extractedMediaForcedNormal = winstonData.extractedMediaForcedNormal?.relayoutingParts(contentWidth: contentWidth, theme: theme)
    }
    // Extracting a repost again would build a new embedded post, losing its votes and
    // previews, so lay the existing one out instead.
    for media in [winstonData.extractedMedia, winstonData.extractedMediaForcedNormal] {
      if case .repost(let embedded) = media {
        embedded.relayout(contentWidth: contentWidth, theme: theme, secondary: true)
      }
    }
    winstonData.postDimensions = getPostDimensions(post: self, winstonData: winstonData, columnWidth: contentWidth, secondary: secondary, rawTheme: theme, subId: sub?.id)
    winstonData.postDimensionsForcedNormal = getPostDimensions(post: self, winstonData: winstonData, columnWidth: contentWidth, secondary: secondary, rawTheme: theme, compact: false)
    winstonData.layoutWidth = contentWidth
    winstonData.layoutWindowHeight = windowHeight
    winstonData.layoutSecondary = secondary
  }
}

extension View {
  /// Re-lays out `posts` when the column width or window height changes (media height is
  /// capped by the window's), after it has settled: resizing a Mac window changes it every frame.
  func relayoutPosts(_ posts: @escaping () -> [Post], contentWidth: Double, theme: WinstonTheme) -> some View {
    self
      .task(id: [contentWidth, Double.screenH]) {
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        posts().forEach { $0.relayout(contentWidth: contentWidth, theme: theme) }
      }
      // Posts can be set up for another width after it settled: feeds fetch with the width they
      // were created with.
      .onChange(of: posts().map { $0.winstonData?.layoutWidth ?? 0 }) {
        posts().forEach { $0.relayout(contentWidth: contentWidth, theme: theme) }
      }
  }
}
