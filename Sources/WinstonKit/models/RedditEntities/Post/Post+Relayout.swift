//
//  Post+Relayout.swift
//  winston
//

import SwiftUI

extension MediaExtractedType {
  /// Image requests and reposts are sized for the column; link previews, videos and embeds
  /// aren't, and extracting a link again would fetch its preview again.
  var dependsOnWidth: Bool {
    switch self {
    case .imgs, .repost: true
    default: false
    }
  }
}

extension Post {
  /// Recomputes media requests and row sizes for a new column width or window height (window
  /// resized, iPhone Duo folded or unfolded). Does nothing if the post was already laid out
  /// for both.
  func relayout(contentWidth: Double, theme: WinstonTheme) {
    guard let winstonData, let data, contentWidth > 0 else { return }
    let windowHeight = Double.screenH
    guard winstonData.layoutWidth != contentWidth || winstonData.layoutWindowHeight != windowHeight else { return }
    let sub = winstonData.subreddit
    if winstonData.extractedMedia?.dependsOnWidth == true {
      winstonData.extractedMedia = mediaExtractor(compact: Post.isCompact(data, sub: sub), contentWidth: contentWidth, data, theme: theme)
    }
    if winstonData.extractedMediaForcedNormal?.dependsOnWidth == true {
      winstonData.extractedMediaForcedNormal = mediaExtractor(compact: false, contentWidth: contentWidth, data, theme: theme)
    }
    winstonData.postDimensions = getPostDimensions(post: self, winstonData: winstonData, columnWidth: contentWidth, rawTheme: theme, subId: sub?.id)
    winstonData.postDimensionsForcedNormal = getPostDimensions(post: self, winstonData: winstonData, columnWidth: contentWidth, rawTheme: theme, compact: false)
    winstonData.layoutWidth = contentWidth
    winstonData.layoutWindowHeight = windowHeight
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
