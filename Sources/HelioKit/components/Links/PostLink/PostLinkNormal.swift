//
//  PostLinkNormal.swift
//  Helio
//
//  Created by Igor Marcossi on 25/09/23.
//

import Defaults
import NukeUI
import SwiftUI

struct PostLinkNormalSelftext: View, Equatable {
  var selftext: String?
  var theme: ThemeText
  var body: some View {
    if let selftext {
      Text(selftext).lineLimit(3)
        .fontSize(theme.size, theme.weight.t)
        .foregroundColor(theme.color())
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    //      .id("body")
  }
}

struct PostLinkNormal: View, Equatable, Identifiable {
  static func == (lhs: PostLinkNormal, rhs: PostLinkNormal) -> Bool {
    lhs.id == rhs.id && lhs.contentWidth == rhs.contentWidth && lhs.secondary == rhs.secondary && lhs.defSettings == rhs.defSettings && lhs.theme == rhs.theme
  }

  @Environment(\.contextPost) var post
  @Environment(\.contextSubreddit) var sub
  @Environment(\.contextPostHelioData) var helioData
  var id: String
  weak var controller: UIViewController?
  var theme: SubPostsListTheme
  var showSub = false
  var secondary = false
  let contentWidth: CGFloat
  let defSettings: PostLinkDefSettings

  func markAsRead() async {
    Task(priority: .background) { await post.toggleSeen(true) }
  }

  func openPost() {
    Nav.to(.reddit(.post(post)))
  }

  func openSubreddit() {
    if let subName = post.data?.subreddit {
      withAnimation {
        Nav.to(.reddit(.subFeed(Subreddit(id: subName))))
      }
    }
  }

  var over18: Bool {
    post.data?.over_18 ?? false
  }

  @ViewBuilder
  func mediaComponentCall() -> some View {
    if let data = post.data {
      if let extractedMedia = helioData.extractedMedia {
        let fullBleed = isFullBleedMedia(extractedMedia, theme: theme.theme, secondary: secondary, compact: false)
        MediaPresenter(helioData: helioData, controller: controller, postTitle: data.title, badgeKit: data.badgeKit, avatarImageRequest: helioData.avatarImageRequest, markAsSeen: !defSettings.lightboxReadsPost ? nil : markAsRead, cornerRadius: fullBleed ? 0 : theme.theme.mediaCornerRadius, blurPostLinkNSFW: defSettings.blurNSFW, media: extractedMedia, over18: over18, compact: false, contentWidth: helioData.postDimensions.mediaSize?.width ?? 0, maxMediaHeightScreenPercentage: defSettings.maxMediaHeightScreenPercentage)
          .allowsHitTesting(defSettings.isMediaTappable)
          .padding(.horizontal, fullBleed ? -theme.theme.innerPadding.horizontal : 0)

        if case let .repost(repost) = extractedMedia {
          if let repostHelioData = repost.helioData, let repostSub = repostHelioData.subreddit {
            PostLink(
              id: repost.id,
              controller: controller,
              theme: theme,
              showSub: true,
              secondary: true,
              compactPerSubreddit: false,
              contentWidth: contentWidth,
              defSettings: defSettings,
            )
            .background(Color.primary.opacity(0.05))
            .cornerRadius(theme.theme.mediaCornerRadius)
            .environment(\.contextPost, repost)
            .environment(\.contextSubreddit, repostSub)
            .environment(\.contextPostHelioData, repostHelioData)
          }
        }
      }
    }
  }

  var body: some View {
    if let data = post.data {
//      let over18 = data.over_18 ?? false
      VStack(alignment: .leading, spacing: theme.theme.verticalElementsSpacing) {
        if theme.theme.showDivider, defSettings.dividerPosition == .top {
          SubsNStuffLine()
        }

        if defSettings.titlePosition == .bottom {
          mediaComponentCall()
        }

        VStack(alignment: .leading, spacing: theme.theme.verticalElementsSpacing / 2.5) {
          PostLinkTitle(attrString: helioData.titleAttr, label: data.title, theme: theme.theme.titleText, size: helioData.postDimensions.titleSize, dimmed: theme.theme.unseenType == .fade && (data.helioSeen ?? false), dimmedColor: theme.theme.badge.statsText.color)

          if !(data.selftext?.isEmpty ?? true), defSettings.showSelfText, let selftext = data.selftext {
            PostLinkNormalSelftext(selftext: selftext, theme: theme.theme.bodyText)
              .lineSpacing(theme.theme.linespacing)
          }
        }

        if defSettings.titlePosition == .top {
          mediaComponentCall()
        }

        if theme.theme.showDivider, defSettings.dividerPosition == .bottom {
          SubsNStuffLine()
        }

        HStack(alignment: .center) {
          let newCommentsCount = helioData.seenCommentsCount == nil ? nil : data.num_comments - helioData.seenCommentsCount!
          BadgeView(avatarRequest: helioData.avatarImageRequest, showAuthorOnPostLinks: defSettings.showAuthor, saved: data.badgeKit.saved, usernameColor: nil, author: data.badgeKit.author, fullname: data.badgeKit.authorFullname, userFlair: data.badgeKit.userFlair, created: data.badgeKit.created, avatarURL: nil, theme: theme.theme.badge, commentsCount: formatBigNumber(data.num_comments), newCommentsCount: newCommentsCount, votesCount: formatBigNumber(data.ups), likes: data.likes, openSub: showSub ? openSubreddit : nil, subName: data.subreddit, onTapStats: openPost, upvoteRatio: defSettings.showUpVoteRatio ? data.upvote_ratio : nil)

          Spacer(minLength: 8)

          // A crosspost's embedded card leaves actions to the post around it.
          if !secondary {
            HStack(spacing: 0) {
              PostLinkMoreMenu(post: post)
              if defSettings.showVotesCluster {
                VotesCluster(votesKit: data.votesKit, voteAction: post.vote, showScore: false, showUpVoteRatio: false)
              }
            }
          }
        }
      }
      .postLinkStyle(post: post, sub: sub, theme: theme.theme, size: helioData.postDimensions.size, secondary: secondary, openPost: openPost, readPostOnScroll: defSettings.readOnScroll)
      .swipyUI(onTap: openPost, actionsSet: defSettings.swipeActions, entity: post, secondary: secondary)
    }
  }
}

// let atr = NSTextAttachment()
// atr.

/// Apollo's "•••" button: the post's actions, the same ones as its context menu.
struct PostLinkMoreMenu: View {
  var post: Post

  var body: some View {
    Menu {
      PostLinkContext(post: post)
      if let permalink = post.data?.permalink {
        Button {
          ShareUtils.shareItem(item: "https://reddit.com\(permalink.escape.urlEncoded)")
        } label: { Label("Share", systemImage: "square.and.arrow.up") }
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: VoteButton.hitSize, height: VoteButton.hitSize)
        .contentShape(Rectangle())
    }
    .accessibilityLabel("More")
  }
}
