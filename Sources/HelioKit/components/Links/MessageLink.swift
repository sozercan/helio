import Defaults
import SwiftUI

struct MessageLink: View {
  var message: Message

  var body: some View {
    if let data = message.data {
      let destination = data.commentDestination
      HStack(alignment: .top) {
        Image(systemName: icon(data, isComment: destination != nil))
          .fontSize(24, .bold)
          .foregroundStyle(iconColor(data, isComment: destination != nil))
        VStack(alignment: .leading, spacing: 2) {
          if destination != nil, let subreddit = data.subreddit {
            Text("**u/\(data.author ?? "[deleted]")** \(action(data)) in **r/\(subreddit)**")
          } else {
            Text(data.subject ?? "Message").fontWeight(.semibold)
            if let sender = sender(data) {
              Text("from **\(sender)**").fontSize(14).opacity(0.75)
            }
          }
          Text((data.body ?? "").md()).lineLimit(destination == nil ? nil : 2).fontSize(15).opacity(0.75)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .themedListRowLikeBG()
      .hairlineRowSeparator()
      .compositingGroup()
      .opacity(!(data.new ?? false) ? 0.65 : 1)
      .contentShape(Rectangle())
      .swipyUI(
        onTap: destination.map { dest in { Nav.to(dest) } },
        actionsSet: SwipeActionsSet(
          id: "message-link-actions",
          leftFirst: AnySwipeAction(NoneAction()),
          leftSecond: AnySwipeAction(NoneAction()),
          rightFirst: AnySwipeAction(ToggleReadMessageAction()),
          rightSecond: AnySwipeAction(NoneAction()),
        ),
        entity: message,
      )
      .contextMenu {
        Button(readToggleTitle(data), systemImage: (data.new ?? false) ? "envelope.open" : "envelope.badge") {
          Task { _ = await message.toggleRead() }
        }
      }
      .accessibilityAction(named: Text(readToggleTitle(data))) {
        Task { _ = await message.toggleRead() }
      }
    }
  }

  private func readToggleTitle(_ data: MessageData) -> String {
    (data.new ?? false) ? "Mark as Read" : "Mark as Unread"
  }

  private func action(_ data: MessageData) -> String {
    switch data.type {
    case "post_reply": "commented on your post"
    case "username_mention": "mentioned you"
    default: "replied to your comment"
    }
  }

  private func sender(_ data: MessageData) -> String? {
    if let author = data.author {
      return "u/\(author)"
    }
    return data.subreddit_name_prefixed ?? data.subreddit.map { "r/\($0)" }
  }

  private func icon(_ data: MessageData, isComment: Bool) -> String {
    guard isComment else { return "envelope.circle.fill" }
    return data.type == "post_reply" ? "message.circle.fill" : "arrowshape.turn.up.left.circle.fill"
  }

  private func iconColor(_ data: MessageData, isComment: Bool) -> Color {
    guard isComment else { return Color.orange }
    return data.type == "post_reply" ? Color.accentColor : Color.green
  }
}
