//
//  MediaPresenter.swift
//  Helio
//
//  Created by Igor Marcossi on 22/08/23.
//

import Defaults
import NukeUI
import SwiftUI
import YouTubePlayerKit

struct OnlyURL: View {
  static let height: Double = 22
  @Default(.BehaviorDefSettings) private var behaviorDefSettings
  var url: URL
  @Environment(\.openURL) private var openURL
  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "link")
      Text(cleanURL(url: url, showPath: false))
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .frame(maxHeight: OnlyURL.height)
    .background(Capsule(style: .continuous).fill(Color.accentColor.opacity(0.3)))
    .fontSize(15, .medium)
    .lineLimit(1)
    .foregroundColor(.white)
    .highPriorityGesture(TapGesture().onEnded {
      if let newURL = URL(string: url.absoluteString.replacingOccurrences(of: "https://reddit.com/", with: "helioapp://")) {
        Nav.openURL(newURL)
      }
    })
  }
}

struct MediaPresenter: View, Equatable {
  static func == (lhs: MediaPresenter, rhs: MediaPresenter) -> Bool {
    lhs.compact == rhs.compact && lhs.contentWidth == rhs.contentWidth && lhs.badgeKit == rhs.badgeKit && lhs.cornerRadius == rhs.cornerRadius && lhs.media == rhs.media
  }

  var helioData: PostHelioData
  var fullPage = false
  weak var controller: UIViewController?
  let postTitle: String
  let badgeKit: BadgeKit
  let avatarImageRequest: ImageRequest?
  let markAsSeen: (() async -> Void)?
  var cornerRadius: Double
  var blurPostLinkNSFW: Bool
  var showURLInstead = false
  let media: MediaExtractedType
  var over18 = false
  let compact: Bool
  let contentWidth: CGFloat
  let maxMediaHeightScreenPercentage: CGFloat

  var body: some View {
    let mediaSize = (fullPage ? helioData.postDimensionsForcedNormal : helioData.postDimensions).mediaSize
    switch media {
    case let .imgs(imgsExtracted):
      if !showURLInstead {
        if !imgsExtracted.isEmpty, imgsExtracted[0].url.absoluteString.hasSuffix(".gif") {
          ImageMediaPost(helioData: helioData, controller: controller, postTitle: postTitle, badgeKit: badgeKit, avatarImageRequest: avatarImageRequest, markAsSeen: markAsSeen, cornerRadius: cornerRadius, compact: compact, images: imgsExtracted, contentWidth: contentWidth, maxMediaHeightScreenPercentage: maxMediaHeightScreenPercentage)
            .nsfw(over18 && blurPostLinkNSFW, smallIcon: compact, size: mediaSize)
        } else {
          ImageMediaPost(helioData: helioData, controller: controller, postTitle: postTitle, badgeKit: badgeKit, avatarImageRequest: avatarImageRequest, markAsSeen: markAsSeen, cornerRadius: cornerRadius, compact: compact, images: imgsExtracted, contentWidth: contentWidth, maxMediaHeightScreenPercentage: maxMediaHeightScreenPercentage)
            .nsfw(over18 && blurPostLinkNSFW, smallIcon: compact, size: mediaSize)
        }
      }
    case let .video(sharedVideo):
      if !showURLInstead {
        VideoPlayerPost(controller: controller, cachedVideo: sharedVideo, markAsSeen: markAsSeen, compact: compact, contentWidth: contentWidth, url: sharedVideo.url, maxMediaHeightScreenPercentage: maxMediaHeightScreenPercentage, cornerRadius: cornerRadius)
          .nsfw(over18 && blurPostLinkNSFW, smallIcon: compact, size: mediaSize)
      }
    case .streamable:
      if !showURLInstead {
        ProgressView()
          .progressViewStyle(.circular)
          .frame(maxWidth: .infinity, minHeight: 100)
          .id("streamable-loading")
          .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)
      }
    case let .yt(ytMediaExtracted):
      if !showURLInstead {
        YTMediaPostPlayer(compact: compact, player: ytMediaExtracted.player, ytMediaExtracted: ytMediaExtracted, contentWidth: contentWidth)
      }
    case let .link(previewModel):
      if let previewURL = previewModel.previewURL {
        if !showURLInstead {
          PreviewLinkContent(compact: compact, viewModel: previewModel, url: previewURL)
        } else {
          OnlyURL(url: previewURL)
        }
      }
    case let .post(postExtractedEntity):
      if let postExtractedEntity {
        if !showURLInstead {
          if compact, let sub = postExtractedEntity.subredditID, let postID = postExtractedEntity.postID {
            if let url = URL(string: "https://reddit.com/r/\(sub)/comments/\(postID)") {
              PreviewLink(url: url, compact: compact, previewModel: PreviewModel(url, compact: compact))
            }
          } else {
            RedditMediaPost(entity: .post(postExtractedEntity.entity))
          }
        } else if let sub = postExtractedEntity.subredditID, let postID = postExtractedEntity.postID, let url = URL(string: "https://reddit.com/r/\(sub)/comments/\(postID)") {
          OnlyURL(url: url)
        }
      }
    case let .comment(commentExtractedEntity):
      if let commentExtractedEntity {
        if !showURLInstead {
          if compact, let sub = commentExtractedEntity.subredditID, let postID = commentExtractedEntity.postID, let commentID = commentExtractedEntity.commentID {
            if let url = URL(string: "https://reddit.com/r/\(sub)/comments/\(postID)/comment/\(commentID)") {
              PreviewLink(url: url, compact: compact, previewModel: PreviewModel(url, compact: compact))
            }
          } else {
            RedditMediaPost(entity: .comment(commentExtractedEntity.entity))
          }
        } else if let sub = commentExtractedEntity.subredditID, let postID = commentExtractedEntity.postID, let commentID = commentExtractedEntity.commentID, let url = URL(string: "https://reddit.com/r/\(sub)/comments/\(postID)/comment/\(commentID)") {
          OnlyURL(url: url)
        }
      }
    case let .subreddit(subExtractedEntity):
      if let subExtractedEntity {
        if !showURLInstead {
          if compact {
            if let url = URL(string: "https://reddit.com/r/\(subExtractedEntity.subredditID ?? "")") {
              PreviewLink(url: url, compact: compact, previewModel: PreviewModel(url, compact: compact))
            }
          } else {
            RedditMediaPost(entity: .subreddit(subExtractedEntity.entity))
          }
        } else if let url = URL(string: "https://reddit.com/r/\(subExtractedEntity.subredditID ?? "")") {
          OnlyURL(url: url)
        }
      }
    case let .user(userExtractedEntity):
      if let userExtractedEntity {
        if !showURLInstead {
          if compact {
            if let url = URL(string: "https://reddit.com/u/\(userExtractedEntity.userID ?? "")") {
              PreviewLink(url: url, compact: compact, previewModel: PreviewModel(url, compact: compact))
            }
          } else {
            RedditMediaPost(entity: .user(userExtractedEntity.entity))
          }
        } else if let url = URL(string: "https://reddit.com/u/\(userExtractedEntity.userID ?? "")") {
          OnlyURL(url: url)
        }
      }
    default:
      EmptyView()
    }
  }
}
