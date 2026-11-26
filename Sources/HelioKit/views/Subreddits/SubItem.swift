import Defaults
import SwiftUI

struct SubItemButton: View, Equatable {
  static func == (lhs: SubItemButton, rhs: SubItemButton) -> Bool {
    lhs.data == rhs.data
  }

  var data: SubredditData
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack {
        Text(data.display_name ?? "")
        SubredditIcon(subredditIconKit: data.subredditIconKit)
      }
    }
  }
}

struct SubItem: View, Equatable {
  static func == (lhs: SubItem, rhs: SubItem) -> Bool {
    lhs.sub == rhs.sub && lhs.sub.data?.user_is_subscriber == rhs.sub.data?.user_is_subscriber && lhs.isActive == rhs.isActive && lhs.inSidebar == rhs.inSidebar
  }

  var isActive: Bool
  var inSidebar: Bool
  var sub: Subreddit
  var cachedSub: CachedSub
  var open: () -> Void
  @Environment(\.backgroundProminence) private var prominence
  @Environment(\.useTheme) private var theme

  func favoriteToggle() {
    sub.favoriteToggle(entity: cachedSub)
  }

  var body: some View {
    if let data = sub.data {
      let favorite = cachedSub.user_has_favorited
      let name = data.display_name ?? sub.id
      HStack {
        Label {
          Text(name)
        } icon: {
          SubredditIcon(subredditIconKit: data.subredditIconKit)
        }

        Spacer()

        Button(favorite ? "Remove from Favorites" : "Add to Favorites", systemImage: "star.fill", action: favoriteToggle)
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
          .foregroundStyle(starColor(favorite: favorite))
          .accessibilityHidden(true)

        if !inSidebar {
          Image(systemName: "chevron.right")
            .fontSize(14, .semibold)
            .opacity(0.35)
            .foregroundStyle(.primary)
        }
      }
      .contentShape(Rectangle())
      .if(!inSidebar) { $0.listRowBackground(ThemedForegroundBG(theme: theme.lists.foreground, active: isActive)) }
      .contextMenu {
        Button("Open", systemImage: "arrow.forward", action: open)
        Button(favorite ? "Remove from Favorites" : "Add to Favorites", systemImage: favorite ? "star.slash" : "star", action: favoriteToggle)
        Button("Share", systemImage: "square.and.arrow.up") {
          ShareUtils.shareItem(item: "https://reddit.com/r/\(name)")
        }
        Divider()
        if data.user_is_subscriber == true {
          Button("Unsubscribe", systemImage: "minus.circle", role: .destructive) {
            sub.subscribeToggle(optimistic: true)
          }
        } else {
          Button("Subscribe", systemImage: "plus.circle") {
            sub.subscribeToggle(optimistic: true)
          }
        }
      }
      .accessibilityValue(favorite ? "Favorite" : "")
      .accessibilityAction(named: favorite ? "Remove from Favorites" : "Add to Favorites", favoriteToggle)
    } else {
      Text("Error")
    }
  }

  private func starColor(favorite: Bool) -> Color {
    if prominence == .increased {
      favorite ? .white : .white.opacity(0.4)
    } else {
      favorite ? .accentColor : .gray.opacity(0.3)
    }
  }
}
