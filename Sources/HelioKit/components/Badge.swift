import Defaults
import Foundation
import NukeUI
import SwiftUI

struct UserFlair: View, Equatable {
  static func == (lhs: UserFlair, rhs: UserFlair) -> Bool {
    lhs.flair == rhs.flair && lhs.subName == rhs.subName && lhs.flairText == rhs.flairText && lhs.flairBackground == rhs.flairBackground
  }

  let flair: String
  var subName: String?
  let flairText: ThemeText
  let flairBackground: ColorSchemes<ThemeColor>

  @State private var emojiURLs: [String: URL] = [:]

  var body: some View {
    let segments = FlairParser.parse(flair)
    let hasEmojis = segments.contains {
      if case .emoji = $0 {
        return true
      }
      return false
    }
    let visible = segments.filter { segment in
      switch segment {
      case .text:
        true
      case let .emoji(name):
        emojiURLs[name] != nil || emojiURLs[name.lowercased()] != nil
      }
    }
    ZStack {
      if !visible.isEmpty {
        HStack(alignment: .center, spacing: 3) {
          ForEach(Array(visible.enumerated()), id: \.offset) { _, segment in
            switch segment {
            case let .text(text):
              Text(text).contentFont(flairText.size, flairText.weight.t, relativeTo: .meta)
                .lineLimit(1)
                .foregroundStyle(flairText.color())
            case let .emoji(name):
              if let url = emojiURLs[name] ?? emojiURLs[name.lowercased()] {
                LazyImage(url: url) { state in
                  if let image = state.image {
                    image.resizable().scaledToFit()
                      .accessibilityLabel(name.replacingOccurrences(of: "_", with: " "))
                  }
                }
                .frame(width: max(12, flairText.size + 2), height: max(12, flairText.size + 2))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(name.replacingOccurrences(of: "_", with: " "))
              }
            }
          }
        }
        .padding(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
        .background(flairBackground())
        .cornerRadius(4.0)
        .allowsHitTesting(false)
      }
    }
    .task(id: hasEmojis ? subName : nil) {
      emojiURLs = [:]
      guard hasEmojis, let subName, !subName.isEmpty else { return }
      let loaded = await SubredditEmojiLoader.shared.emojiURLs(for: subName)
      guard !Task.isCancelled else { return }
      emojiURLs = loaded
    }
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
  @Environment(\.navColumn) private var navColumn
  static let authorStatsSpacing: Double = 6
  static func == (lhs: BadgeView, rhs: BadgeView) -> Bool {
    lhs.avatarURL == rhs.avatarURL && lhs.saved == rhs.saved && lhs.avatarRequest?.url == rhs.avatarRequest?.url && lhs.theme == rhs.theme && lhs.commentsCount == rhs.commentsCount && lhs.newCommentsCount == rhs.newCommentsCount && lhs.votesCount == rhs.votesCount && lhs.likes == rhs.likes && lhs.userFlair == rhs.userFlair && lhs.subName == rhs.subName
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
  var onTapStats: (() -> Void)?
  var upvoteRatio: Double?

  nonisolated func openUser() {
    Nav.to(.reddit(.user(User(id: author))), from: navColumn)
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
              .accessibilityLabel("u/\(author)")

              if unseen {
                PostLinkGlowDot(unseenType: .dot(commentTheme?.unseenDot ?? ColorSchemes<ThemeColor>(light: .init(hex: "FF0000"), dark: .init(hex: "FF0000"))), seen: false, badge: true).equatable()
              }

              if let userFlair, !FlairParser.parse(userFlair).isEmpty {
                UserFlair(flair: userFlair, subName: subName, flairText: theme.flairText, flairBackground: theme.flairBackground).equatable()
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
          }

          HStack(alignment: .center, spacing: theme.statsText.size * 0.62) {
            if let votesCount {
              BadgeStat(icon: likes == false ? "arrow.down" : "arrow.up", text: votesCount, label: likes == nil ? "\(votesCount) points" : "\(votesCount) points, \(likes == true ? "upvoted" : "downvoted")")
                .foregroundStyle(theme.voteColor(likes, neutral: defaultIconColor))
            }

            if let upvoteRatio {
              let percent = Int((upvoteRatio * 100).rounded())
              BadgeStat(icon: "face.smiling", text: "\(percent)%", label: "\(percent)% upvoted")
            }

            if let commentsCount {
              BadgeStat(icon: "bubble.left", text: commentsCount, label: "\(commentsCount) comments")
            }

            if let newComments = newCommentsCount, newComments > 0 {
              Text("+\(newComments)").foregroundStyle(theme.newCommentsText?.color() ?? Color.accentColor)
                .accessibilityLabel("\(newComments) new")
            }

            BadgeStat(icon: "clock", text: timeSince(Int(created)), label: spokenTimeSince(Int(created)))

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

struct BadgeStat: View {
  var icon: String
  var text: String
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

  var body: some View {
    if let data = post.data {
      BadgeView(saved: data.saved, usernameColor: usernameColor, author: data.author, userFlair: data.author_flair_text, created: data.created, avatarURL: avatarURL, theme: theme, commentsCount: formatBigNumber(data.num_comments), votesCount: !showVotes ? nil : formatBigNumber(data.ups), subName: data.subreddit)
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
