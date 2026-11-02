//
//  SubItem.swift
//  Helio
//
//  Created by Igor Marcossi on 05/08/23.
//

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
    lhs.sub == rhs.sub && lhs.isActive == rhs.isActive
  }

  var isActive: Bool
  var sub: Subreddit
  var cachedSub: CachedSub
  var action: (Subreddit) -> Void
//  @Default(.likedButNotSubbed) private var likedButNotSubbed

  func favoriteToggle() {
//    guard let sub = sub else { return }
//    if likedButNotSubbed.contains(sub) {
//      _ = sub.localFavoriteToggle()
//    } else {
    sub.favoriteToggle(entity: cachedSub)
//    }
  }

  var body: some View {
    if let data = sub.data {
      let favorite = cachedSub.user_has_favorited
//      let localFav = likedButNotSubbed.contains(sub)
//      let isActive = selectedSub == .reddit(.subFeed(sub))
      WListButton(showArrow: !isWideLayout, active: isActive) {
        action(sub)
      } label: {
        HStack {
          Label {
            Text(data.display_name ?? "")
              .foregroundStyle(isActive ? .white : .primary)
          } icon: {
            SubredditIcon(subredditIconKit: data.subredditIconKit)
          }

          Spacer()

          // A gesture inside the row button's label, which VoiceOver reads as one element:
          // VoiceOver gets the toggle as an action of the row instead.
          Image(systemName: "star.fill")
            .foregroundColor(favorite ? Color.accentColor : .gray.opacity(0.3))
            .highPriorityGesture(TapGesture().onEnded(favoriteToggle))
            .accessibilityHidden(true)
        }
      }
      .accessibilityValue(favorite ? "Favorite" : "")
      .accessibilityAction(named: favorite ? "Remove from Favorites" : "Add to Favorites", favoriteToggle)

    } else {
      Text("Error")
    }
  }
}
