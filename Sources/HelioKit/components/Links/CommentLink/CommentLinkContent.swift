//
//  CommentLinkContent.swift
//  Helio
//
//  Created by Igor Marcossi on 08/07/23.
//

import Defaults
import MarkdownUI
import NukeUI
import SwiftUI

struct CommentLinkContentPreview: View {
  var forcedBodySize: CGSize?
  var showReplies = true
  var arrowKinds: [ArrowKind]
  var indentLines: Int?
  var lineLimit: Int?
  var post: Post?
  var comment: Comment
  var avatarsURL: [String: String]?
  var body: some View {
    if let helioData = comment.helioData, let forcedBodySize {
      VStack(alignment: .leading, spacing: 0) {
        CommentLinkContent(forcedBodySize: nil, showReplies: showReplies, arrowKinds: arrowKinds, indentLines: indentLines, lineLimit: lineLimit, post: post, comment: comment, helioData: helioData, avatarsURL: avatarsURL)
      }
//      .frame(width: .screenW, height: forcedBodySize.height + CGFloat((data.depth != 0 ? 42 : 30) + 16))
      .padding(.vertical, 12)
      .frame(width: .screenW)
      .fixedSize()
    }
  }
}

struct CommentLinkContent: View {
  static let indentLineContentSpacing: Double = 4
  static let indentLinesSpacing: Double = 6

  var disableBG = false
  var highlightID: String?
  var seenComments: String?
  var forcedBodySize: CGSize?
  var showReplies = true
  var arrowKinds: [ArrowKind]
  var indentLines: Int?
  var lineLimit: Int?
  var post: Post?
  var comment: Comment
  var helioData: CommentHelioData
  var avatarsURL: [String: String]?
  /// Replies hidden under this comment while it's collapsed.
  var hiddenReplyCount = 0

  @SilentState private var size: CGSize = .zero
  @State private var offsetX: CGFloat = 0
  @State private var highlight = false
  @State private var showSpoiler = false
  @State private var commentSwipeActions: SwipeActionsSet = CachedDefaults[.CommentLinkDefSettings].swipeActions

  @Default(.CommentLinkDefSettings) private var defSettings
  @Default(.CommentsSectionDefSettings) private var sectionDefSettings

  @Environment(\.useTheme) private var selectedTheme

  @State var commentViewLoaded = false

  nonisolated func haptic() {
    Task(priority: .background) {
      let medium = await UIImpactFeedbackGenerator(style: .medium)
      await medium.prepare()
      await medium.impactOccurred()
    }
  }

  var body: some View {
    let theme = selectedTheme.comments
    let selectable = (comment.data?.helioSelecting ?? false)
    let horPad = theme.theme.innerPadding.horizontal
    let bars = !theme.theme.indentColors.isEmpty

    if let data = comment.data {
      let collapsed = data.collapsed ?? false
      // `indentLines` overrides the depth, like the reply sheet's unindented preview.
      let barDepth = bars ? (indentLines ?? data.depth ?? 0) : nil
      let headerLineHeight = max(theme.theme.badge.authorText.size * 1.25, theme.theme.badge.avatar.visible ? theme.theme.badge.avatar.size : 0)
      let headerTopPad = max(0, theme.theme.innerPadding.vertical + (data.depth == 0 ? -theme.theme.cornerRadius : theme.theme.repliesSpacing))
      Group {
        HStack(spacing: CommentLinkContent.indentLineContentSpacing) {
          if !bars, data.depth != 0, indentLines != 0 {
            HStack(alignment: .bottom, spacing: CommentLinkContent.indentLinesSpacing) {
              let shapes = Array(1 ... Int(indentLines ?? data.depth ?? 1))
              ForEach(shapes, id: \.self) { i in
                if arrowKinds.indices.contains(i - 1) {
                  let actualArrowKind = arrowKinds[i - 1]
                  Arrows(kind: actualArrowKind, offset: theme.theme.innerPadding.vertical + theme.theme.repliesSpacing)
                }
              }
            }
          }
          HStack(spacing: 8) {
            if bars {
              CommentHeaderLine(data: data, avatarRequest: helioData.avatarImageRequest, isOP: (post?.data?.author ?? "") == data.author, unseen: seenComments == nil ? false : !seenComments!.contains(data.id), theme: theme.theme)
            } else if let author = data.author {
              BadgeView(avatarRequest: helioData.avatarImageRequest, saved: data.badgeKit.saved, unseen: seenComments == nil ? false : !seenComments!.contains(data.id), usernameColor: (post?.data?.author ?? "") == author ? Color.green : nil, author: data.badgeKit.author, fullname: data.badgeKit.authorFullname, userFlair: data.badgeKit.userFlair, created: data.badgeKit.created, theme: theme.theme.badge, commentTheme: theme.theme)
            }

            Spacer()

            if data.saved ?? false {
              Image(systemName: "bookmark.fill")
                .fontSize(14)
                .foregroundColor(.green)
                .transition(.scale.combined(with: .opacity))
            }

            if selectable {
              HStack(spacing: 2) {
                Circle()
                  .fill(.white)
                  .frame(width: 8, height: 8)
                Text("SELECTING")
              }
              .fontSize(13, .medium)
              .foregroundColor(.white)
              .padding(.horizontal, 6)
              .padding(.vertical, 1)
              .background(.orange, in: Capsule(style: .continuous))
              .onTapGesture { withAnimation { comment.data?.helioSelecting = false } }
            }

            if bars {
              if collapsed, hiddenReplyCount > 0 {
                Text("+\(formatBigNumber(hiddenReplyCount))")
                  .font(.system(size: theme.theme.badge.statsText.size, weight: .medium))
                  .foregroundStyle(theme.theme.badge.statsText.color())
                  .padding(.horizontal, 6)
                  .background(theme.theme.loadMoreBackground(), in: Capsule(style: .continuous))
              }
              Text(timeSince(Int(data.badgeKit.created)))
                .font(.system(size: theme.theme.badge.statsText.size, weight: theme.theme.badge.statsText.weight.t))
                .foregroundStyle(theme.theme.badge.statsText.color())
            } else if let ups = data.ups {
              HStack(alignment: .center, spacing: 4) {
                Image(systemName: "arrow.up")
                  .foregroundColor(data.likes != nil && data.likes! ? .orange : .gray)
                  .contentShape(Rectangle())
                  .onTapGesture {
                    Task {
                      haptic()
                      _ = await comment.vote(action: .up)
                    }
                  }

                let downup = Int(ups)
                Text(data.score_hidden == true ? "–" : formatBigNumber(downup))
                  .accessibilityLabel(data.score_hidden == true ? "Score hidden" : "\(downup) points")
                  .foregroundColor(data.likes != nil ? (data.likes! ? .orange : .blue) : .gray)
                  .contentTransition(.numericText())
                  //                  .foregroundColor(downup == 0 ? .gray : downup > 0 ? .orange : .blue)
                  .fontSize(14, .semibold)

                Image(systemName: "arrow.down")
                  .foregroundColor(data.likes != nil && !data.likes! ? .blue : .gray)
                  .contentShape(Rectangle())
                  .onTapGesture {
                    Task {
                      haptic()
                      _ = await comment.vote(action: .down)
                    }
                  }
              }
              .fontSize(14, .medium)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Capsule(style: .continuous).fill(.secondary.opacity(0.1)))
              //              .viewVotes(ups, downs)
              .allowsHitTesting(!collapsed)
              .scaleEffect(1)

              if collapsed {
                HStack(spacing: 2) {
                  Image(systemName: "eye.slash.fill")
                  if hiddenReplyCount > 0 {
                    Text("+\(formatBigNumber(hiddenReplyCount))")
                  }
                }
                .fontSize(14, .medium)
                .opacity(0.5)
                .allowsHitTesting(false)
              }
            }
          }
          .padding(.top, headerTopPad)
          .compositingGroup()
          .opacity(collapsed && !bars ? 0.5 : 1)
          .contentShape(Rectangle())
          .offset(x: offsetX)
          .animation(draggingAnimation, value: offsetX)
          .swipyUI(
            controlledDragAmount: $offsetX,
            controlledIsSource: false,
            onTap: { withAnimation(spring) { comment.toggleCollapsed(optimistic: true) } },
            actionsSet: commentSwipeActions,
            entity: comment,
            skipAnimation: true,
          )
        }
        .padding(.horizontal, bars ? 0 : horPad)
        .frame(height: (bars ? headerLineHeight : max((theme.theme.badge.authorText.size * 1.2) + (theme.theme.badge.statsText.size * 1.2) + 2, theme.theme.badge.avatar.size)) + headerTopPad, alignment: .leading)
        .padding(.bottom, bars && collapsed ? theme.theme.innerPadding.vertical : 0)
        .commentDepthBar(barDepth, theme: theme.theme, top: max(0, headerTopPad - 2), bottom: collapsed ? 8 : 0, separator: true)
        .mask(Color.black)
        // The header's vote arrows are gone in this style, so keep voting reachable for VoiceOver.
        .accessibilityAction(named: "Upvote") { Task { _ = await comment.vote(action: .up) } }
        .accessibilityAction(named: "Downvote") { Task { _ = await comment.vote(action: .down) } }
        .onAppear {
          if !commentViewLoaded, sectionDefSettings.collapseAutoModerator {
            if data.depth == 0, data.author == "AutoModerator", !(data.collapsed ?? false) {
              comment.toggleCollapsed(optimistic: true)
            }
          } else {
            commentViewLoaded = true
          }
        }
        .id("\(data.id)-header\(forcedBodySize == nil ? "" : "-preview")")

        if !collapsed {
          HStack(spacing: CommentLinkContent.indentLineContentSpacing) {
            if !bars, data.depth != 0, indentLines != 0 {
              HStack(alignment: .bottom, spacing: CommentLinkContent.indentLinesSpacing) {
                let shapes = Array(1 ... Int(indentLines ?? data.depth ?? 1))
                ForEach(shapes, id: \.self) { i in
                  if arrowKinds.indices.contains(i - 1) {
                    let actualArrowKind = arrowKinds[i - 1]
                    Arrows(kind: actualArrowKind.child)
                  }
                }
              }
              .mask(Rectangle())
            }
            if let body = data.body {
              VStack {
                Group {
                  if lineLimit != nil {
                    Text(body)
                      .lineLimit(lineLimit)
                  } else {
                    HStack {
                      Markdown(MarkdownUtil.markdownContent(body, showSpoiler: showSpoiler))
                        .markdownTheme(.helioMarkdown(fontSize: theme.theme.bodyText.size, lineSpacing: theme.theme.linespacing, textSelection: selectable))
                        .fixedSize(horizontal: false, vertical: true)

                      if MarkdownUtil.containsSpoiler(body) {
                        Spacer()
                        Image(systemName: showSpoiler ? "eye.slash.fill" : "eye.fill")
                          .onTapGesture {
                            withAnimation {
                              showSpoiler.toggle()
                            }
                          }
                      }
                    }
                  }
                }
                .fontSize(theme.theme.bodyText.size, theme.theme.bodyText.weight.t)
                .foregroundColor(theme.theme.bodyText.color())
              }
              .offset(x: offsetX)
              .animation(draggingAnimation, value: offsetX)
              .swipyUI(
                offsetYAction: -15,
                controlledDragAmount: $offsetX,
                onTap: {
                  if !selectable {
                    withAnimation(spring) { comment.toggleCollapsed(optimistic: true) }
                  }
                },
                actionsSet: commentSwipeActions,
                entity: comment,
                skipAnimation: true,
              )
              .frame(maxWidth: .infinity, alignment: .topLeading)
              .padding(.top, theme.theme.bodyAuthorSpacing)
              .padding(.bottom, bars ? theme.theme.innerPadding.vertical : max(0, theme.theme.innerPadding.vertical + (data.depth == 0 && comment.childrenHelio.isEmpty ? -theme.theme.cornerRadius : theme.theme.innerPadding.vertical)))
              .scaleEffect(1)
              .contentShape(Rectangle())
              .measure($size)
            } else {
              Spacer()
            }
          }
          .padding(.horizontal, bars ? 0 : horPad)
          .commentDepthBar(barDepth, theme: theme.theme, bottom: 8)
          .mask(Color.black.padding(.top, -(data.depth != 0 ? 42 : 30)).padding(.bottom, -8))
          .id("\(data.id)-body\(forcedBodySize == nil ? "" : "-preview")")
        }
      }
      .background(Color.accentColor.opacity(highlight ? 0.2 : 0))
      .background(showReplies ? theme.theme.bg() : .clear)
      .onAppear {
        let newCommentSwipeActions = Defaults[.CommentLinkDefSettings].swipeActions
        if commentSwipeActions != newCommentSwipeActions {
          commentSwipeActions = newCommentSwipeActions
        }
        if var specificID = highlightID {
          specificID = specificID.hasPrefix("t1_") ? String(specificID.dropFirst(3)) : specificID
          if specificID == data.id {
            withAnimation { highlight = true }
          }
          doThisAfter(0.1) {
            withAnimation(.easeOut(duration: 4)) { highlight = false }
          }
        }
      }
      .contextMenu {
        if !selectable, forcedBodySize == nil {
          ForEach(allCommentSwipeActions) { action in
            let active = action.active(comment)
            if action.enabled(comment) {
              Button {
                Task(priority: .background) {
                  await action.action(comment)
                }
              } label: {
                Label(active ? "Undo \(action.label.lowercased())" : action.label, systemImage: active ? action.icon.active : action.icon.normal)
                  .foregroundColor(action.bgColor.normal == "353439" ? action.color.normal == "FFFFFF" ? Color.blue : Color.hex(action.color.normal) : Color.hex(action.bgColor.normal))
              }
            }
          }

          if let body = data.body, !body.isEmpty {
            Button {
              Nav.present(.selectText(body))
            } label: { Label("Select Text", systemImage: "selection.pin.in.out") }
          }

          if let permalink = data.permalink {
            // ShareLink inside a .contextMenu is a known SwiftUI bug; present imperatively instead.
            Button {
              ShareUtils.shareItem(item: "https://reddit.com\(permalink.escape.urlEncoded)")
            } label: { Label("Share", systemImage: "square.and.arrow.up") }
          }
        }
      } preview: {
        CommentLinkContentPreview(forcedBodySize: size, showReplies: showReplies, arrowKinds: arrowKinds, indentLines: indentLines, lineLimit: lineLimit, post: post, comment: comment, avatarsURL: avatarsURL)
          .id("\(data.id)-preview")
      }
    } else {
      Text("oops")
    }
  }
}

/// Apollo's comment header: author, flair and score on one line.
struct CommentHeaderLine: View {
  var data: CommentData
  var avatarRequest: ImageRequest?
  var isOP: Bool
  var unseen: Bool
  var theme: CommentTheme

  var body: some View {
    let badge = theme.badge
    HStack(alignment: .center, spacing: 6) {
      if badge.avatar.visible, let author = data.author {
        AvatarView(saved: data.saved ?? false, avatarImgRequest: avatarRequest, userID: author, fullname: data.author_fullname, theme: badge.avatar)
      }

      if let author = data.author {
        Text(author)
          .font(.system(size: badge.authorText.size, weight: badge.authorText.weight.t))
          .foregroundStyle(author == "[deleted]" ? .red : isOP ? Color.accentColor : badge.authorText.color())
          .lineLimit(1)
          .onTapGesture { Nav.to(.reddit(.user(User(id: author)))) }
      }

      if unseen {
        PostLinkGlowDot(unseenType: .dot(theme.unseenDot), seen: false, badge: true).equatable()
      }

      if let flairs = flairWithoutEmojis(str: data.author_flair_text) {
        ForEach(flairs, id: \.self) {
          UserFlair(flair: $0, flairText: badge.flairText, flairBackground: badge.flairBackground).equatable()
        }
      }

      if let ups = data.ups {
        BadgeStat(icon: data.likes == false ? "arrow.down" : "arrow.up", text: data.score_hidden == true ? "–" : formatBigNumber(ups))
          .font(.system(size: badge.statsText.size, weight: badge.statsText.weight.t))
          .foregroundStyle(data.likes == nil ? badge.statsText.color() : data.likes == true ? Color.upvote : Color.downvote)
          .accessibilityLabel(data.score_hidden == true ? "Score hidden" : "\(ups) points")
      }
    }
  }
}

// struct CommentLinkContent_Previews: PreviewProvider {
//    static var previews: some View {
//        CommentLinkContent()
//    }
// }

struct AnimatingCellHeight: AnimatableModifier {
  var height: CGFloat = 0
  var disable: Bool = false

  var animatableData: CGFloat {
    get { height }
    set { height = newValue }
  }

  func body(content: Content) -> some View {
    content.frame(height: disable ? nil : height, alignment: .topLeading)
  }
}
