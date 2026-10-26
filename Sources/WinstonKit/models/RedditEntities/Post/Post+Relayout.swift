//
//  Post+Relayout.swift
//  winston
//

import SwiftUI

extension Post {
  /// Recomputes media requests and row sizes for a new column width (window resized, iPhone
  /// Duo folded or unfolded). Does nothing if the post was already laid out for this width.
  func relayout(contentWidth: Double, theme: WinstonTheme) {
    guard let winstonData, contentWidth > 0 else { return }
    let expected = getPostContentWidth(contentWidth: contentWidth, theme: theme)
    guard abs(winstonData.postDimensions.contentWidth - expected) > 0.5 else { return }
    setupWinstonData(winstonData: winstonData, contentWidth: contentWidth, theme: theme, sub: winstonData.subreddit, fetchAvatar: false)
  }
}

extension View {
  /// Re-lays out `posts` when the column width changes, after it has settled: resizing a Mac
  /// window changes the width every frame.
  func relayoutPosts(_ posts: @escaping () -> [Post], contentWidth: Double, theme: WinstonTheme) -> some View {
    self
      .task(id: contentWidth) {
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        posts().forEach { $0.relayout(contentWidth: contentWidth, theme: theme) }
      }
      // Feeds fetch with the width they were created with, so posts that arrive after the
      // width changed (the sidebar appearing on launch) were set up for the old one.
      .onChange(of: posts().map(\.id)) {
        posts().forEach { $0.relayout(contentWidth: contentWidth, theme: theme) }
      }
  }
}
