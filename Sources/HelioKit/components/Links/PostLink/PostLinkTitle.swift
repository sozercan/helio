//
//  PostLinkTitle.swift
//  Helio
//
//  Created by Igor Marcossi on 25/09/23.
//

import SwiftUI

struct PostLinkTitle: View, Equatable {
  static func == (lhs: PostLinkTitle, rhs: PostLinkTitle) -> Bool {
    lhs.label == rhs.label && lhs.size == rhs.size && lhs.theme == rhs.theme && lhs.dimmed == rhs.dimmed
  }

  var attrString: NSAttributedString?
  var label: String
  var theme: ThemeText
  var size: CGSize
  /// Read posts get a muted title, like Apollo.
  var dimmed = false
  var dimmedColor: ColorSchemes<ThemeColor>?

  var body: some View {
    if let attrString {
      Prepend(attrString: attrString, title: label, fontWeight: theme.weight.ut, color: (dimmed ? dimmedColor ?? theme.color : theme.color).uiColor(), size: size)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }
    //                  Text(label)
    //                    .fontSize(theme.size, theme.weight.t)
    //                    .fixedSize(horizontal: false, vertical: true)
    //                    .frame(maxWidth: .infinity, alignment: .topLeading)
  }
}

extension View {
  /// The feed title, drawn by a UIKit label VoiceOver can't read, as a button that opens the
  /// post, with the post's actions (the ones in its context menu and swipe actions).
  func postTitleAccessibility(post: Post, data: PostData, open: @escaping () -> Void) -> some View {
    // The element is a clear view behind the title: the label itself runs taller than the
    // title (it lays out blank lines below it), and VoiceOver would outline all of it.
    accessibilityHidden(true)
      .background {
        Color.clear
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(postTitleAccessibilityLabel(data))
          .accessibilityAddTraits(.isButton)
          .accessibilityHint("Opens the post")
          .accessibilityAction(.default, open)
          .accessibilityActions { PostAccessibilityActions(post: post) }
      }
  }
}

/// The post's context menu, as VoiceOver actions.
private struct PostAccessibilityActions: View {
  var post: Post

  var body: some View {
    PostLinkContext(post: post)
    Button("Share") {
      if let permalink = post.data?.permalink {
        ShareUtils.shareItem(item: "https://reddit.com\(permalink.escape.urlEncoded)")
      }
    }
  }
}

/// The title and the tags drawn after it: "Title, NSFW, Flair".
func postTitleAccessibilityLabel(_ data: PostData) -> String {
  var parts = [data.title]
  if data.over_18 ?? false {
    parts.append("NSFW")
  }
  if let flair = flairWithoutEmojis(str: data.link_flair_text)?.joined(separator: " "), !flair.isEmpty {
    parts.append(flair)
  }
  return parts.joined(separator: ", ")
}
