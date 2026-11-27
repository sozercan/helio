import Defaults
import SwiftUI

struct CommentSkipper: View {
  @Binding var topVisibleCommentId: String?
  @Binding var previousScrollTarget: String?

  var comments: [Comment]
  var seenComments: String?
  var activeUsername: String?
  var userScrollGeneration: Int = 0
  var currentVisibleCommentID: () -> String? = { nil }
  var reader: ScrollViewProxy

  @Default(.CommentsSectionDefSettings) private var commentsSectionDefSettings
  @State private var lastNewCommentTarget: String?
  @State private var suppressNextTap = false

  var body: some View {
    let mode = commentsSectionDefSettings.commentSkipperMode
    let newTargets = mode == .newComments
      ? CommentJumpNavigator.targetIDs(
        roots: comments,
        mode: .newComments,
        seenComments: seenComments,
        activeUsername: activeUsername,
      )
      : []
    let isNewModeActive = !newTargets.isEmpty

    Button {
      if suppressNextTap {
        suppressNextTap = false
        return
      }
      Hap.shared.play(intensity: 0.75, sharpness: 0.9)
      withAnimation {
        jump(direction: 1, newTargets: newTargets)
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
        suppressNextTap = true
        Hap.shared.play(intensity: 0.75, sharpness: 0.9)
        withAnimation {
          jump(direction: -1, newTargets: newTargets)
        }
      },
    )
    .onChange(of: userScrollGeneration) { _, _ in
      lastNewCommentTarget = nil
    }
    .accessibilityLabel(isNewModeActive ? "Jump to Next New Comment" : "Jump to Next Comment")
    .accessibilityHint("Long press to jump to previous")
  }

  private func jump(direction: Int, newTargets: [String]) {
    if !newTargets.isEmpty {
      let current = lastNewCommentTarget ?? currentVisibleCommentID() ?? topVisibleCommentId
      let ordered = lastNewCommentTarget == nil ? CommentJumpNavigator.orderedCommentIDs(roots: comments) : []
      guard let next = CommentJumpNavigator.step(targets: newTargets, orderedIDs: ordered, currentID: current, direction: direction) else { return }
      reader.scrollTo(next, anchor: .top)
      lastNewCommentTarget = next
      return
    }

    let threadTargets = comments.map(\.id)
    if direction < 0 {
      let current = topVisibleCommentId ?? previousScrollTarget
      guard let prev = CommentJumpNavigator.step(targets: threadTargets, currentID: current, direction: -1) else { return }
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
      let topVisibleCommentIndex = threadTargets.firstIndex(of: topVisibleCommentId) ?? 0
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
