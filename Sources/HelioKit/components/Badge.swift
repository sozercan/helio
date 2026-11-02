//
//  Badge.swift
//  Helio
//
//  Created by Igor Marcossi on 01/07/23.
//

import Defaults
import Foundation
import NukeUI
import SwiftUI

struct UserFlair: View, Equatable {
  let flair: String
  let flairText: ThemeText
  let flairBackground: ColorSchemes<ThemeColor>

  var body: some View {
    Text(flair).contentFont(flairText.size, flairText.weight.t, relativeTo: .meta)
      .lineLimit(1)
      .foregroundColor(flairText.color())
      .padding(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
      .background(flairBackground())
      .cornerRadius(4.0)
      .allowsHitTesting(false)
  }
}

struct BadgeKit: Equatable {
  let numComments: Int
  let ups: Int
  let saved: Bool
  let author: String
  let authorFullname: String
  let userFlair: String
  let created: Double
}

private let flairEmojiRegex = try? NSRegularExpression(pattern: ":(.*?):")

func flairWithoutEmojis(str: String?) -> [String]? {
  guard let flairEmojiRegex, let s = str else { return nil }
  let sep = "<separator>"
  return flairEmojiRegex.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: s.count), withTemplate: sep)
    .components(separatedBy: sep).map { str in
      str.replacingOccurrences(of: sep, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { str in
      !str.isEmpty
    }
}

struct BadgeView: View, Equatable {
  static let authorStatsSpacing: Double = 6
  static func == (lhs: BadgeView, rhs: BadgeView) -> Bool {
    lhs.avatarURL == rhs.avatarURL && lhs.saved == rhs.saved && lhs.avatarRequest?.url == rhs.avatarRequest?.url && lhs.theme == rhs.theme && lhs.commentsCount == rhs.commentsCount && lhs.newCommentsCount == rhs.newCommentsCount && lhs.votesCount == rhs.votesCount && lhs.likes == rhs.likes
  }

  var avatarRequest: ImageRequest?
  var showAuthorOnPostLinks = true
  var saved = false
  var unseen = false
  var usernameColor: Color?
  var author: String
  var userFlair: String?
  var created: Double
  var avatarURL: String?
  var theme: BadgeTheme
  var commentTheme: CommentTheme?
  var commentsCount: String?
  var newCommentsCount: Int?
  var votesCount: String?
  var likes: Bool?
  var openSub: (() -> Void)?
  var subName: String?
  /// Makes the numbers line its own tap target. Without one, a tap on it goes to the nearest
  /// tappable view, the author's name, instead of the row.
  var onTapStats: (() -> Void)?
  /// Shown next to the score when set, for the "Show upvote ratio" setting.
  var upvoteRatio: Double?

  nonisolated func openUser() {
    Nav.to(.reddit(.user(User(id: author))))
  }

  var body: some View {
    let showAvatar = theme.avatar.visible
    let defaultIconColor = theme.statsText.color()
    let showSubName = openSub != nil && subName != nil
    let showsFirstLine = showAuthorOnPostLinks || (showSubName && !theme.forceSubsAsTags)
    HStack(spacing: theme.spacing) {
      if showAvatar {
        AvatarView(saved: saved, avatarImgRequest: avatarRequest, userID: author, theme: theme.avatar)
          .highPriorityGesture(TapGesture().onEnded(openUser))
      }

      // Apollo's two lines: who and where, then the numbers.
      VStack(alignment: .leading, spacing: BadgeView.authorStatsSpacing) {
        if showsFirstLine {
          HStack(alignment: .center, spacing: 4) {
            if let openSub, let subName {
              Button(action: openSub) {
                if theme.forceSubsAsTags {
                  Tag(subredditIconKit: nil, text: "r/\(subName)", fontSize: theme.authorText.size, backgroundColor: theme.subColor())
                } else {
                  Text(subName).foregroundStyle(theme.subColor())
                    .contentFont(theme.authorText.size, theme.authorText.weight.t, relativeTo: .meta).lineLimit(1)
                }
              }
              .buttonStyle(.plain)
              .hoverEffect(.highlight)
              .accessibilityLabel("r/\(subName)")
            }

            if showAuthorOnPostLinks {
              if showSubName {
                Text("·").foregroundStyle(theme.authorText.color().opacity(0.6))
                  .accessibilityHidden(true)
              }
              Button(action: openUser) {
                Text(author)
                  .contentFont(theme.authorText.size, showSubName ? .regular : theme.authorText.weight.t, relativeTo: .meta)
                  .foregroundStyle(author == "[deleted]" ? .red : usernameColor ?? theme.authorText.color())
                  .lineLimit(1)
              }
              .buttonStyle(.plain)
              .hoverEffect(.highlight)
              .accessibilityLabel("u/\(author)")

              if unseen {
                PostLinkGlowDot(unseenType: .dot(commentTheme?.unseenDot ?? ColorSchemes<ThemeColor>(light: .init(hex: "FF0000"), dark: .init(hex: "FF0000"))), seen: false, badge: true).equatable()
              }

              if let flairs = flairWithoutEmojis(str: userFlair) {
                // TODO: Load flair emojis via GET /api/v1/{subreddit}/emojis/{emoji_name}
                ForEach(flairs, id: \.self) {
                  UserFlair(flair: $0, flairText: theme.flairText, flairBackground: theme.flairBackground).equatable()
                }
              }
            }

            if saved, !showAvatar {
              Image(systemName: "bookmark.fill")
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Saved")
            }
          }
          .contentFont(theme.authorText.size, relativeTo: .meta)
        }

        HStack(alignment: .center, spacing: theme.statsText.size * 0.62) {
          if let openSub, let subName, theme.forceSubsAsTags, !showAuthorOnPostLinks {
            Button(action: openSub) {
              Tag(subredditIconKit: nil, text: "r/\(subName)", fontSize: theme.statsText.size, backgroundColor: theme.subColor())
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
          }

          // The numbers read as one element, "4.8K points, 1.3K comments, 2 hours ago".
          HStack(alignment: .center, spacing: theme.statsText.size * 0.62) {
            if let votesCount {
              BadgeStat(icon: likes == false ? "arrow.down" : "arrow.up", text: votesCount, label: likes == nil ? "\(votesCount) points" : "\(votesCount) points, \(likes == true ? "upvoted" : "downvoted")")
                .foregroundStyle(likes == nil ? defaultIconColor : likes == true ? Color.upvoteText : Color.downvoteText)
            }

            if let upvoteRatio {
              let percent = Int((upvoteRatio * 100).rounded())
              BadgeStat(icon: "face.smiling", text: "\(percent)%", label: "\(percent)% upvoted")
            }

            if let commentsCount {
              BadgeStat(icon: "bubble.left", text: commentsCount, label: "\(commentsCount) comments")
            }

            if let newComments = newCommentsCount, newComments > 0 {
              Text("+\(newComments)").foregroundStyle(Color.accentColor)
                .accessibilityLabel("\(newComments) new")
            }

            BadgeStat(icon: "clock", text: timeSince(Int(created)), label: spokenTimeSince(Int(created)))

            // The first line holds the saved mark; without it, show it here.
            if saved, !showAvatar, !showsFirstLine {
              Image(systemName: "bookmark.fill").foregroundStyle(.green)
                .accessibilityLabel("Saved")
            }
          }
          .accessibilityElement(children: .combine)
        }
        .foregroundStyle(defaultIconColor)
        .contentFont(theme.statsText.size, theme.statsText.weight.t, relativeTo: .meta)
        .contentShape(Rectangle())
        .onTapGesture { onTapStats?() }
        .allowsHitTesting(onTapStats != nil)
      }
    }
    .geometryGroup()
    .animation(showAvatar ? nil : spring.delay(0.4), value: saved)
  }
}

/// An outline SF Symbol and its number, like Apollo's meta line.
struct BadgeStat: View {
  var icon: String
  var text: String
  /// What VoiceOver reads instead of the symbol's name and the number, like "1.3K comments".
  var label: String

  var body: some View {
    HStack(alignment: .center, spacing: 3) {
      Image(systemName: icon).imageScale(.small)
      Text(text).contentTransition(.numericText())
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
  }
}

struct Badge: View {
  var showVotes = false
  var post: Post
  var usernameColor: Color?
  var avatarURL: String?
  var theme: BadgeTheme
  //  var extraInfo: [BadgeExtraInfo] = []

  var body: some View {
    if let data = post.data {
      BadgeView(saved: data.saved, usernameColor: usernameColor, author: data.author, userFlair: data.author_flair_text, created: data.created, avatarURL: avatarURL, theme: theme, commentsCount: formatBigNumber(data.num_comments), votesCount: !showVotes ? nil : formatBigNumber(data.ups))
    }
  }
}

struct BadgeOpt: View, Equatable {
  static func == (lhs: BadgeOpt, rhs: BadgeOpt) -> Bool {
    lhs.badgeKit == rhs.badgeKit && lhs.theme == rhs.theme && lhs.avatarRequest?.url == rhs.avatarRequest?.url
  }

  var avatarRequest: ImageRequest?
  let badgeKit: BadgeKit
  var showVotes = false
  var usernameColor: Color?
  var avatarURL: String?
  var theme: BadgeTheme
  var openSub: (() -> Void)?
  var subName: String?

  var body: some View {
    BadgeView(avatarRequest: avatarRequest, saved: badgeKit.saved, usernameColor: usernameColor, author: badgeKit.author, userFlair: badgeKit.userFlair, created: badgeKit.created, avatarURL: avatarURL, theme: theme, commentsCount: formatBigNumber(badgeKit.numComments), votesCount: !showVotes ? nil : formatBigNumber(badgeKit.ups), openSub: openSub, subName: subName)
  }
}
