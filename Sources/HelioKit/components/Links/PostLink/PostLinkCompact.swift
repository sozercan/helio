//
//  PostLinkCompact.swift
//  Helio
//
//  Created by Igor Marcossi on 25/09/23.
//

import Defaults
import NukeUI
import SwiftUI

struct PostLinkCompactThumbPlaceholder: View, Equatable {
  var theme: PostLinkTheme.CompactSelftextPostLinkPlaceholderImg

  var body: some View {
    let scaledCompactModeThumbSize = scaledCompactModeThumbSize()
    Group {
      if theme.type == .helio {
        Image(systemName: "sun.max")
          .resizable()
      } else {
        Image(systemName: "square.text.square")
          .resizable()
      }
    }
    .scaledToFill()
    .padding(scaledCompactModeThumbSize * 0.075)
    .frame(scaledCompactModeThumbSize)
    .foregroundStyle(theme.color())
  }
}

struct PostLinkCompact: View, Equatable, Identifiable {
  static func == (lhs: PostLinkCompact, rhs: PostLinkCompact) -> Bool {
    lhs.id == rhs.id && lhs.theme == rhs.theme && lhs.contentWidth == rhs.contentWidth && lhs.defSettings == rhs.defSettings
  }

  var id: String
  @Environment(\.contextPost) var post
  @Environment(\.contextSubreddit) var sub
  @Environment(\.contextPostHelioData) var helioData
  weak var controller: UIViewController?
  var theme: SubPostsListTheme
  var showSub = false
  var secondary: Bool
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
      Nav.to(.reddit(.subFeed(Subreddit(id: subName))))
    }
  }

  var over18: Bool {
    post.data?.over_18 ?? false
  }

  @ViewBuilder
  func mediaComponentCall(showURLInstead: Bool = false) -> some View {
    if let data = post.data, let extractedMedia = post.helioData?.extractedMedia {
      MediaPresenter(helioData: helioData, controller: controller, postTitle: data.title, badgeKit: data.badgeKit, avatarImageRequest: helioData.avatarImageRequest, markAsSeen: !defSettings.lightboxReadsPost ? nil : markAsRead, cornerRadius: theme.theme.mediaCornerRadius, blurPostLinkNSFW: defSettings.blurNSFW, showURLInstead: showURLInstead, media: extractedMedia, over18: over18, compact: true, contentWidth: helioData.postDimensions.mediaSize?.width ?? 0, maxMediaHeightScreenPercentage: defSettings.maxMediaHeightScreenPercentage)
        .allowsHitTesting(defSettings.isMediaTappable)
    }
  }

  @ViewBuilder
  func votesPiece() -> some View {
    if let data = post.data, defSettings.showVotesCluster {
      VotesCluster(votesKit: data.votesKit, voteAction: post.vote, vertical: true, showUpVoteRatio: defSettings.showUpVoteRatio).fontSize(22, .medium)
        .fontSize(22, .medium)
    }
  }

  @ViewBuilder
  func mediaPiece() -> some View {
    if let extractedMedia = post.helioData?.extractedMedia {
      if case let .repost(repost) = extractedMedia, let repostData = repost.data, let url = URL(string: "https://reddit.com/r/\(repostData.subreddit)/comments/\(repost.id)") {
        PreviewLink(url: url, compact: true, previewModel: PreviewModel(url, compact: true))
      } else {
        mediaComponentCall()
      }
    } else if defSettings.compactMode.showPlaceholderThumbnail {
      PostLinkCompactThumbPlaceholder(theme: theme.theme.compactSelftextPostLinkPlaceholderImg).equatable()
    }
  }

  var body: some View {
    if let data = post.data {
      VStack(alignment: .leading, spacing: theme.theme.verticalElementsSpacing) {
        HStack(alignment: .top, spacing: theme.theme.verticalElementsSpacing) {
          if defSettings.compactMode.voteButtonsSide == .leading {
            votesPiece()
          }

          if defSettings.compactMode.thumbnailSide == .leading {
            mediaPiece()
          }

          VStack(alignment: .leading, spacing: theme.theme.verticalElementsSpacing) {
            VStack(alignment: .leading, spacing: theme.theme.verticalElementsSpacing / 2) {
              PostLinkTitle(attrString: helioData.titleAttr, label: data.title, theme: theme.theme.titleText, size: helioData.postDimensions.titleSize)

              if let extractedMedia = post.helioData?.extractedMedia {
                if case let .repost(repost) = extractedMedia, let repostData = repost.data, let url = URL(string: "https://reddit.com/r/\(repostData.subreddit)/comments/\(repost.id)") {
                  OnlyURL(url: url)
                }
                mediaComponentCall(showURLInstead: true)
              }
            }

            let newCommentsCount = helioData.seenCommentsCount == nil ? nil : data.num_comments - helioData.seenCommentsCount!
            BadgeView(avatarRequest: helioData.avatarImageRequest, showAuthorOnPostLinks: defSettings.showAuthor, saved: data.badgeKit.saved, usernameColor: nil, author: data.badgeKit.author, fullname: data.badgeKit.authorFullname, userFlair: data.badgeKit.userFlair, created: data.badgeKit.created, avatarURL: nil, theme: theme.theme.badge, commentsCount: formatBigNumber(data.badgeKit.numComments), newCommentsCount: newCommentsCount, votesCount: formatBigNumber(data.badgeKit.ups), likes: data.likes, openSub: !theme.theme.badge.avatar.visible && showSub ? openSubreddit : nil, subName: data.subreddit)

            if showSub, theme.theme.badge.avatar.visible {
              let subName = data.subreddit
              Tag(subredditIconKit: nil, text: "r/\(subName)", color: theme.theme.badge.subColor())
                .highPriorityGesture(TapGesture().onEnded(openSubreddit))
            }
          }
          .frame(maxWidth: .infinity, alignment: .topLeading)

          if defSettings.compactMode.thumbnailSide == .trailing {
            mediaPiece()
          }

          if defSettings.compactMode.voteButtonsSide == .trailing {
            votesPiece()
          }
        }
        .zIndex(1)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
      .postLinkStyle(showSubBottom: showSub && theme.theme.badge.avatar.visible, post: post, sub: sub, theme: theme.theme, size: helioData.postDimensions.size, secondary: secondary, openPost: openPost, readPostOnScroll: defSettings.readOnScroll)
      .swipyUI(onTap: openPost, actionsSet: defSettings.swipeActions, entity: post)
//      .frame(width: helioData.postDimensions.size.width, height: helioData.postDimensions.size.height)
    }
  }
}
