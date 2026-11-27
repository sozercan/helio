import SwiftUI

struct PostLinkTitle: View, Equatable {
  static func == (lhs: PostLinkTitle, rhs: PostLinkTitle) -> Bool {
    lhs.attrString === rhs.attrString && lhs.label == rhs.label && lhs.size == rhs.size && lhs.theme == rhs.theme && lhs.dimmed == rhs.dimmed
  }

  var attrString: NSAttributedString?
  var label: String
  var theme: ThemeText
  var size: CGSize
  var dimmed = false
  var dimmedColor: ColorSchemes<ThemeColor>?

  var body: some View {
    if let attrString {
      Prepend(attrString: attrString, title: label, fontWeight: theme.weight.ut, color: (dimmed ? dimmedColor ?? theme.color : theme.color).uiColor(), size: size)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

extension View {
  func postTitleAccessibility(post: Post, data: PostData, secondary: Bool, open: @escaping () -> Void) -> some View {
    accessibilityHidden(true)
      .background {
        Color.clear
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(postTitleAccessibilityLabel(data))
          .accessibilityAddTraits(.isButton)
          .modifier(OpenPostSelectedTrait(postID: post.id, marks: !secondary))
          .accessibilityHint("Opens the post")
          .accessibilityAction(.default, open)
          .accessibilityActions { PostMenuItems(post: post) }
      }
  }
}

struct PostMenuItems: View {
  var post: Post

  var body: some View {
    PostLinkContext(post: post)
    if let data = post.data, !data.title.isEmpty {
      Button("Translate", systemImage: "translate") {
        Nav.present(.translateText(OnDeviceTranslation.postTranslationText(title: data.title, selftext: data.selftext)))
      }
    }
    Button("Share", systemImage: "square.and.arrow.up") {
      if let permalink = post.data?.permalink {
        ShareUtils.shareItem(item: "https://reddit.com\(permalink.escape.urlEncoded)")
      }
    }
  }
}

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

struct OpenPostSelectedTrait: ViewModifier {
  let postID: String
  let marks: Bool
  @Environment(\.navColumn) private var navColumn

  func body(content: Content) -> some View {
    content.accessibilityAddTraits(marks && isOpenBesideFeed(postID: postID, column: navColumn) ? .isSelected : [])
  }
}
