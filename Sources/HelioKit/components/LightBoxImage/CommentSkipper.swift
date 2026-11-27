import Defaults
import SwiftUI

struct CommentSkipper: View {
  @Binding var topVisibleCommentId: String?
  @Binding var previousScrollTarget: String?

  var comments: [Comment]
  var seenComments: String?
  var activeUsername: String?
  var reader: ScrollViewProxy

  @Default(.CommentsSectionDefSettings) private var commentsSectionDefSettings
  @State private var lastNewCommentTarget: String?

  private var mode: CommentSkipperMode {
    commentsSectionDefSettings.commentSkipperMode
  }

  private var targets: [String] {
    let resolved = CommentJumpNavigator.targetIDs(
      roots: comments,
      mode: mode,
      seenComments: seenComments,
      activeUsername: activeUsername,
    )
    return resolved.isEmpty ? comments.map(\.id) : resolved
  }

  private var isNewModeActive: Bool {
    mode == .newComments && !CommentJumpNavigator.targetIDs(
      roots: comments,
      mode: .newComments,
      seenComments: seenComments,
      activeUsername: activeUsername,
    ).isEmpty
  }

  var body: some View {
    Button {
      Hap.shared.play(intensity: 0.75, sharpness: 0.9)
      withAnimation {
        jump(direction: 1)
      }
    } label: {
      VStack(spacing: 1) {
        if isNewModeActive {
          Text("NEW")
            .font(.system(size: 8, weight: .bold))
            .tracking(0.4)
        }
        Image(systemName: "chevron.down")
          .fontSize(isNewModeActive ? 16 : 20, .semibold)
      }
      .frame(width: 56, height: 56)
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(isNewModeActive ? Color.accentColor : .primary)
    .floating()
    .simultaneousGesture(
      LongPressGesture(minimumDuration: 0.35).onEnded { _ in
        Hap.shared.play(intensity: 0.75, sharpness: 0.9)
        withAnimation {
          jump(direction: -1)
        }
      },
    )
    .accessibilityLabel(isNewModeActive ? "Jump to Next New Comment" : "Jump to Next Comment")
    .accessibilityHint("Long press to jump to previous")
  }

  private func jump(direction: Int) {
    if isNewModeActive {
      let current = lastNewCommentTarget ?? topVisibleCommentId
      guard let next = CommentJumpNavigator.step(targets: targets, currentID: current, direction: direction) else { return }
      reader.scrollTo(next, anchor: .top)
      lastNewCommentTarget = next
      return
    }

    if direction < 0 {
      let current = previousScrollTarget ?? topVisibleCommentId
      guard let prev = CommentJumpNavigator.step(targets: targets, currentID: current, direction: -1) else { return }
      reader.scrollTo(prev, anchor: .top)
      topVisibleCommentId = prev
      previousScrollTarget = prev
      return
    }

    if topVisibleCommentId == nil, let id = comments.first?.id {
      reader.scrollTo(id, anchor: .top)
      topVisibleCommentId = id
      return
    }

    if let topVisibleCommentId {
      let topVisibleCommentIndex = comments.map(\.id).firstIndex(of: topVisibleCommentId) ?? 0
      if topVisibleCommentId == previousScrollTarget {
        let nextIndex = min(topVisibleCommentIndex + 1, comments.count - 1)
        reader.scrollTo(comments[nextIndex].id, anchor: .top)
        previousScrollTarget = nextIndex < comments.count - 1 ? comments[nextIndex + 1].id : nil
      } else {
        let nextIndex = min(topVisibleCommentIndex + 1, comments.count - 1)
        reader.scrollTo(comments[nextIndex].id, anchor: .top)
        previousScrollTarget = topVisibleCommentId
      }
    }
  }
}
