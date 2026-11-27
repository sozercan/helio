import SwiftUI

struct MultiLink: View {
  var multi: Multi
  var selected = false
  @State private var subs: [Subreddit] = []

  var body: some View {
    Menu {
      ForEach(subs) { sub in
        if let data = sub.data {
          SubItemButton(data: data, action: { Nav.selectFeed(.reddit(.subFeed(sub))) })
        }
      }
    } label: {
      VStack(spacing: 10) {
        if let imgLink = multi.data?.icon_url, let imgURL = URL(string: imgLink) {
          URLImage(url: imgURL)
            .scaledToFill()
            .frame(width: 72, height: 72)
            .mask(Circle())
            .overlay {
              if selected {
                Circle().strokeBorder(Color.accentColor, lineWidth: 2)
              }
            }
        }
        Text(multi.data?.display_name ?? "")
          .foregroundStyle(selected ? Color.accentColor : .primary)
          .fontSize(15, .medium)
      }
      .multilineTextAlignment(.center)
      .contentShape(Rectangle())
    } primaryAction: {
      Nav.selectFeed(.reddit(.multiFeed(multi)))
    }
    .accessibilityAddTraits(selected ? .isSelected : [])
    .onAppear {
      if subs.isEmpty {
        subs = multi.data?.subreddits?.compactMap { sub in
          if let data = sub.data {
            return Subreddit(data: data)
          }
          return nil
        } ?? []
      }
    }
  }
}
