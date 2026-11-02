//
//  PostContent.swift
//  Helio
//
//  Created by Igor Marcossi on 31/07/23.
//

import AVFoundation
import AVKit
import Defaults
import MarkdownUI
import SwiftUI

struct PostContent: View, Equatable {
  static func == (lhs: PostContent, rhs: PostContent) -> Bool {
    lhs.post.id == rhs.post.id
  }

  var post: Post
  var helioData: PostHelioData
  var forceCollapse: Bool = false
  @State private var collapsed = false
  @State private var showSpoiler = false
  @Default(.PostPageDefSettings) private var defSettings
  // Markdown sets its own font sizes, so bodies scale by passing a scaled size in.
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.useTheme) private var selectedTheme
  @Environment(\.contentWidth) private var contentWidth

  @Environment(\.navColumn) private var navColumn

  func openSubreddit() {
    if let subName = post.data?.subreddit {
      // From the column the post is in: a post at the feed column's root opens it there.
      Nav.to(.reddit(.subFeed(Subreddit(id: subName))), from: navColumn)
    }
  }

  var body: some View {
    let postsTheme = selectedTheme.posts
    let isCollapsed = forceCollapse || collapsed
    let data = post.data ?? emptyPostData
    let over18 = data.over_18 ?? false
    Group {
      if post.data == nil {
        VStack {
          ProgressView()
            .progressViewStyle(.circular)
            // Fills the post's list until the post loads.
            .containerRelativeFrame(.vertical) { height, _ in max(0, height - 200) }
            .frame(maxWidth: .infinity)
            .id("post-loading")
        }
      }

      Group {
        HStack {
          Text(data.title)
            .contentFont(postsTheme.titleText.size, .semibold, relativeTo: .title)
            .accessibilityAddTraits(.isHeader)
            .foregroundColor(postsTheme.titleText.color())
            .fixedSize(horizontal: false, vertical: true)
            .id("post-title")
            .onAppear { Task { await post.toggleSeen(true) } }
            .listRowInsets(EdgeInsets(top: postsTheme.padding.vertical, leading: postsTheme.padding.horizontal, bottom: postsTheme.spacing / 2, trailing: selectedTheme.posts.padding.horizontal))

          if MarkdownUtil.containsSpoiler(data.selftext ?? "") {
            Spacer()
            SpoilerToggle(showSpoiler: $showSpoiler)
          }
        }

        Group {
          if !isCollapsed {
            VStack(spacing: 0) {
              VStack(spacing: selectedTheme.posts.spacing) {
                if let layout = post.pageLayout(contentWidth: contentWidth, theme: selectedTheme), let extractedMedia = layout.media {
                  // The feed's size runs full-bleed images edge to edge; the post page keeps them inset.
                  let feedTheme = selectedTheme.postLinks.theme
                  let fullBleedInset = isFullBleedMedia(extractedMedia, theme: feedTheme, secondary: false, compact: false) ? feedTheme.innerPadding.horizontal * 2 : 0
                  MediaPresenter(helioData: helioData, fullPage: true, controller: nil, postTitle: data.title, badgeKit: data.badgeKit, avatarImageRequest: helioData.avatarImageRequest, markAsSeen: {}, cornerRadius: selectedTheme.postLinks.theme.mediaCornerRadius, blurPostLinkNSFW: defSettings.blurNSFW, media: extractedMedia, over18: over18, compact: false, contentWidth: (layout.mediaSize?.width ?? 0) - fullBleedInset, maxMediaHeightScreenPercentage: Defaults[.PostLinkDefSettings].maxMediaHeightScreenPercentage)
                }

                if !(data.selftext?.isEmpty ?? true) {
                  HStack {
                    Markdown(MarkdownUtil.markdownContent(data.selftext ?? "", showSpoiler: showSpoiler))
                      .markdownTheme(.helioMarkdown(fontSize: ContentTextScale.size(selectedTheme.posts.bodyText.size, dynamicTypeSize: dynamicTypeSize), lineSpacing: selectedTheme.posts.linespacing, textSelection: true))
                      .fixedSize(horizontal: false, vertical: true)

                    Spacer()
                  }
                }
              }
              .nsfw(over18 && defSettings.blurNSFW)
            }
          } else {
            Text("*Collapsed...*").foregroundStyle(.secondary).font(.caption)
          }
        }
        .id("post-content")
        .listRowInsets(EdgeInsets(top: postsTheme.spacing / 2, leading: postsTheme.padding.horizontal, bottom: postsTheme.spacing / 2, trailing: postsTheme.spacing / 2))
      }
      .contentShape(Rectangle())
      .onTapGesture { withAnimation(.smooth) { collapsed.toggle() } }

      BadgeOpt(avatarRequest: helioData.avatarImageRequest, badgeKit: data.badgeKit, showVotes: false, theme: postsTheme.badge,
               openSub: openSubreddit, subName: data.subreddit)
        .id("post-badge")
        .listRowInsets(EdgeInsets(top: postsTheme.spacing / 2, leading: postsTheme.padding.horizontal, bottom: postsTheme.spacing * 0.75, trailing: postsTheme.padding.horizontal))

      SubsNStuffLine()
        .id("post-flair-divider")
        .listRowInsets(EdgeInsets(top: 0, leading: postsTheme.padding.horizontal, bottom: postsTheme.commentsDistance / 2, trailing: postsTheme.padding.horizontal))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .multilineTextAlignment(.leading)
  }
}
