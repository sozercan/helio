import Defaults
import SwiftUI

struct SubredditLinkContainer: View {
  var noHPad = false
  var sub: Subreddit
  var body: some View {
    SubredditLink(noHPad: true, sub: sub)
  }
}

struct SubredditLink: View {
  @Environment(\.navColumn) private var navColumn
  var noHPad = false
  var sub: Subreddit
  var body: some View {
    if let data = sub.data {
      @State var isSubbed = data.user_is_subscriber ?? false
      HStack(spacing: 12) {
        SubredditIcon(subredditIconKit: data.subredditIconKit, size: 64)
          .nsfw(Defaults[.PostLinkDefSettings].blurNSFW ? data.over18 ?? false : false, smallIcon: true)

        VStack(alignment: .leading) {
          HStack {
            Text("r/\(data.display_name ?? "?")")
              .fontSize(18, .semibold)
            Spacer()
            SubscribeButton(subreddit: sub, isSmall: true)
              .frame(height: 24)
          }
          Text("\(formatBigNumber(data.subscribers ?? 0)) subscribers")
            .fontSize(14).foregroundStyle(Color.secondaryText)
          Text((data.public_description).md()).lineLimit(2)
            .fontSize(15).opacity(0.75)
        }
      }
      .padding(.horizontal, noHPad ? 0 : 16)
      .padding(.vertical, 14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .themedListRowLikeBG(disableBG: noHPad)
      .if(noHPad) { $0.mask(RR(20, .black)) }
      .if(!noHPad) { $0.hairlineRowSeparator() }
      .onTapGesture {
        Nav.to(.reddit(.subFeed(sub)), from: navColumn)
      }
    }
  }
}
