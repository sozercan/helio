//
//  getPostContentWidth.swift
//  Helio
//
//  Created by Igor Marcossi on 24/09/23.
//

import Defaults
import Foundation
import SwiftUI

func getPostContentWidth(contentWidth: Double = .screenW, secondary: Bool = false, theme: HelioTheme? = nil) -> CGFloat {
  let selectedTheme = theme ?? InMemoryTheme.shared.currentTheme
  let theme = selectedTheme.postLinks.theme
  return contentWidth - (((theme.innerPadding.horizontal * (secondary ? 2 : 1)) + theme.outerHPadding) * 2)
}

/// Flat, edge-to-edge cells run images and videos to the cell edges, like Apollo. Cards keep them inset.
func isFullBleedMedia(_ media: MediaExtractedType?, theme: PostLinkTheme, secondary: Bool, compact: Bool) -> Bool {
  guard !compact, !secondary, theme.outerHPadding == 0 else { return false }
  switch media {
  case .imgs, .video: return true
  default: return false
  }
}

struct PostDimensions: Hashable, Equatable {
  static var zero: PostDimensions {
    PostDimensions(contentWidth: 0, titleSize: .zero, dividerSize: .zero, badgeSize: .zero, spacingHeight: 0)
  }

  let contentWidth: Double
  let titleSize: CGSize
  var bodySize: CGSize?
  var urlTagHeight: Double?
  var mediaSize: CGSize?
  var dividerSize: CGSize?
  var badgeSize: CGSize
  var spacingHeight: Double
  var padding: CGSize {
    self.theme.innerPadding.toSize()
  }

  var theme: PostLinkTheme
  var compact: Bool
  var size: CGSize {
    let tagHeight = urlTagHeight == nil ? 0 : (self.spacingHeight / 2) + (self.urlTagHeight ?? 0)
    let compactHeight = max(self.titleSize.height + self.spacingHeight + self.badgeSize.height + tagHeight, (mediaSize?.height ?? 0))
    let normalHeight = self.titleSize.height + (self.bodySize?.height ?? 0) + (self.mediaSize?.height ?? 0) + (self.dividerSize?.height ?? 00) + self.badgeSize.height + self.spacingHeight
    return CGSize(
      width: self.contentWidth + (self.padding.width * 2),
      height: (self.compact ? compactHeight : normalHeight) + (self.padding.height * 2),
    )
  }

  init(contentWidth: Double, compact: Bool? = nil, theme: PostLinkTheme? = nil, titleSize: CGSize, bodySize: CGSize? = nil, urlTagHeight: Double? = nil, mediaSize: CGSize? = nil, dividerSize: CGSize? = nil, badgeSize: CGSize, spacingHeight: Double) {
    self.contentWidth = contentWidth
    self.compact = compact ?? CachedDefaults[.PostLinkDefSettings].compactMode.enabled
    self.theme = theme ?? InMemoryTheme.shared.currentTheme.postLinks.theme
    self.titleSize = titleSize
    self.bodySize = bodySize
    self.urlTagHeight = urlTagHeight
    self.mediaSize = mediaSize
    self.dividerSize = dividerSize
    self.badgeSize = badgeSize
    self.spacingHeight = spacingHeight
  }
}

func getPostDimensions(post: Post, helioData: PostHelioData? = nil, columnWidth: Double = .screenW, secondary: Bool = false, rawTheme: HelioTheme? = nil, compact: Bool? = nil, subId: String? = nil) -> PostDimensions {
  if let data = post.data {
    let selectedTheme = rawTheme ?? InMemoryTheme.shared.currentTheme
    let showSelfPostThumbnails = CachedDefaults[.PostLinkDefSettings].compactMode.showPlaceholderThumbnail
    let compact = compact ?? CachedDefaults[.SubredditFeedDefSettings].compactPerSubreddit[subId ?? data.subreddit_id ?? ""] ?? CachedDefaults[.PostLinkDefSettings].compactMode.enabled
    let showAuthorOnPostLinks = CachedDefaults[.PostLinkDefSettings].showAuthor
    let maxDefaultHeight: CGFloat = CachedDefaults[.PostLinkDefSettings].maxMediaHeightScreenPercentage
    let maxHeight: CGFloat = (maxDefaultHeight / 100) * .screenH
    let extractedMedia = compact ? helioData?.extractedMedia : helioData?.extractedMediaForcedNormal
    let compactImgSize = scaledCompactModeThumbSize()
    let theme = selectedTheme.postLinks.theme
    let postGeneralSpacing = theme.verticalElementsSpacing + theme.linespacing
    let title = data.title
    let body = data.selftext ?? ""

    var ACC_titleHeight: Double = 0
    var ACC_bodyHeight: Double = 0

    let contentWidth: CGFloat = columnWidth - (((theme.innerPadding.horizontal * (secondary ? 2 : 1)) + theme.outerHPadding) * 2)

    let mediaWidth = contentWidth + (isFullBleedMedia(extractedMedia, theme: theme, secondary: secondary, compact: compact) ? theme.innerPadding.horizontal * 2 : 0)

    var ACC_mediaSize: CGSize = .zero
    let compactMediaSize = CGSize(width: compactImgSize, height: compactImgSize)

    var urlTagHeight: Double? = nil
    if compact {
      ACC_mediaSize = extractedMedia != nil || showSelfPostThumbnails ? compactMediaSize : .zero
    } else {
      if let extractedMedia {
        func defaultMediaSize(_ size: CGSize, width: CGFloat) -> CGSize {
          // Square when Reddit gives no dimensions, like the media views, so the row doesn't
          // start empty and jump once the media loads. Not the cached layout's size: it was
          // capped to the window height, so it isn't the media's shape.
          let knownSize = size.width > 0 && size.height > 0 ? size : CGSize(width: width, height: width)
          let sourceHeight = knownSize.height
          let sourceWidth = knownSize.width
          let propHeight = (width * sourceHeight) / (sourceWidth == 0 ? 1 : sourceWidth)
          let finalHeight = maxDefaultHeight != 110 ? Double(min(maxHeight, propHeight)) : Double(propHeight)
          return CGSize(width: width, height: finalHeight)
        }

        switch extractedMedia {
        case let .imgs(mediaExtracted):
          if mediaExtracted.count == 1 {
            ACC_mediaSize = defaultMediaSize(mediaExtracted[0].size, width: mediaWidth)
          } else if mediaExtracted.count > 1 {
            let size = ((mediaWidth - 8) / 2)
            ACC_mediaSize = mediaExtracted.count == 2 ? CGSize(width: mediaWidth, height: size) : CGSize(width: mediaWidth, height: (size * 2) + ImageMediaPost.gallerySpacing)
          }
        case let .video(video):
          ACC_mediaSize = defaultMediaSize(video.size, width: mediaWidth)
        case .streamable:
          ACC_mediaSize = CGSize(width: contentWidth, height: 100)
        case let .yt(ytMediaExtracted):
          let size = ytMediaExtracted.size
          let actualHeight = (contentWidth * CGFloat(size.height)) / CGFloat(size.width)
          ACC_mediaSize = CGSize(width: contentWidth, height: actualHeight)
        case .link:
          ACC_mediaSize = CGSize(width: contentWidth, height: PreviewLinkContentRaw.height)
        case let .repost(repost):
          if let repostSize = repost.helioData?.postDimensions {
            ACC_mediaSize = repostSize.size
          }
        case .post:
          ACC_mediaSize = CGSize(width: contentWidth, height: RedditMediaPost.height)
        case .comment:
          ACC_mediaSize = CGSize(width: contentWidth, height: RedditMediaPost.height)
        case .subreddit:
          ACC_mediaSize = CGSize(width: contentWidth, height: RedditMediaPost.height)
        case .user:
          ACC_mediaSize = CGSize(width: contentWidth, height: RedditMediaPost.height)
        }
      }
    }

    if let extractedMedia {
      switch extractedMedia {
      case .link, .post, .comment, .subreddit, .user, .repost:
        urlTagHeight = OnlyURL.height
      default:
        break
      }
    }

    // Text posts without a placeholder thumbnail get no thumbnail column.
    let compactTitleWidth = postGeneralSpacing + VotesCluster.verticalWidth + (ACC_mediaSize.width > 0 ? postGeneralSpacing + ACC_mediaSize.width : 0)

    let titleContentWidth = contentWidth - (compact ? compactTitleWidth : 0)

    var appendStr = ""
    let titleAttr = NSMutableAttributedString(string: title, attributes: [.font: UIFont.systemFont(ofSize: theme.titleText.size + 0.35, weight: theme.titleText.weight.ut)])
    let titleAttrBlankSpace = NSAttributedString(string: "   ", attributes: [.font: UIFont.systemFont(ofSize: theme.titleText.size + 0.35, weight: theme.titleText.weight.ut)])
    if data.over_18 ?? false {
      titleAttr.append(titleAttrBlankSpace)
      appendStr += "NSFW"
    }
    if let flair = flairWithoutEmojis(str: data.link_flair_text)?.first, !flair.isEmpty {
      titleAttr.append(titleAttrBlankSpace)
      appendStr += flair
    }
    let append = NSMutableAttributedString(string: appendStr, attributes: [.font: UIFont.systemFont(ofSize: ((theme.titleText.size - 2) * 100) / 120, weight: .semibold)])
    if !appendStr.isEmpty {
      titleAttr.append(append)
      titleAttr.append(titleAttrBlankSpace)
    }
    ACC_titleHeight = round(titleAttr.boundingRect(with: CGSize(width: titleContentWidth, height: .infinity), options: [.usesLineFragmentOrigin], context: nil).height)

    if !body.isEmpty && !compact {
      ACC_bodyHeight = round(NSString(string: body).boundingRect(with: CGSize(width: contentWidth, height: (theme.bodyText.size * 1.2) * 3), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: [.font: UIFont.systemFont(ofSize: theme.bodyText.size, weight: theme.bodyText.weight.ut)], context: nil).height)
    }

    ACC_mediaSize.width = round(ACC_mediaSize.width)
    ACC_mediaSize.height = round(ACC_mediaSize.height)

    let ACC_SubDividerHeight = SubsNStuffLine.height

    let badgeAvatarHeight = theme.badge.avatar.visible ? theme.badge.avatar.size : 0
    let badgeAuthorHeight = theme.badge.authorText.size * 1.2
    let badgeStatsFontHeight = theme.badge.statsText.size * 1.2
    let badgeAuthorStatsSpacing = BadgeView.authorStatsSpacing

    let ACC_badgeHeight = round(max(badgeAvatarHeight, (showAuthorOnPostLinks ? badgeAuthorHeight + badgeAuthorStatsSpacing : 0) + badgeStatsFontHeight))

    let theresTitle = true
    let theresSelftext = !compact && !(data.selftext?.isEmpty ?? true)
    let theresMedia = extractedMedia != nil
    let theresSubDivider = !compact && theme.showDivider
    let theresBadge = true
    let elements = [theresTitle, theresSelftext, !compact && theresMedia, theresSubDivider, theresBadge]
    let ACC_allSpacingsHeight = Double(elements.filter(\.self).count - 1) * postGeneralSpacing

    //    let ACC_verticalPadding = theme.innerPadding.vertical * 2

    //    let totalHeight = ACC_titleHeight + ACC_bodyHeight + ACC_mediaSize.height + ACC_SubDividerHeight + ACC_badgeHeight + ACC_verticalPadding + ACC_allSpacingsHeight

    return PostDimensions(
      contentWidth: contentWidth,
      compact: compact,
      theme: theme,
      titleSize: CGSize(width: titleContentWidth, height: ACC_titleHeight + 1),
      bodySize: !theresSelftext || compact ? nil : CGSize(width: contentWidth, height: ACC_bodyHeight),
      urlTagHeight: urlTagHeight,
      mediaSize: !theresMedia ? nil : compact ? compactMediaSize : CGSize(width: mediaWidth, height: ACC_mediaSize.height),
      dividerSize: compact ? nil : CGSize(width: contentWidth, height: ACC_SubDividerHeight),
      badgeSize: CGSize(width: contentWidth, height: ACC_badgeHeight),
      spacingHeight: ACC_allSpacingsHeight,
    )
  }
  return .zero
}
