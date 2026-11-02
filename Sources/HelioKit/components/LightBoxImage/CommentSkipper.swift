//
//  CommentSkipper.swift
//  OpenArtemis
//
//  Created by daniel on 12/8/23.
//

import SwiftUI

/// The post page's "jump to the next comment" button, in its bottom bar.
struct CommentSkipper: View {
  @Binding var topVisibleCommentId: String?
  @Binding var previousScrollTarget: String?

  var comments: [Comment]
  var reader: ScrollViewProxy

  var body: some View {
    Button {
      Hap.shared.play(intensity: 0.75, sharpness: 0.9)
      withAnimation {
        jumpToNextComment()
      }
    } label: {
      Label("Jump to Next Comment", systemImage: "chevron.down")
        .labelStyle(.iconOnly)
        .fontSize(20, .semibold)
        .frame(width: 56, height: 56)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(.primary)
    .floating()
  }

  private func jumpToNextComment() {
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
//        print(comments.count)
//        print(comments)
//        print("------------")
//        print(nextIndex)
        reader.scrollTo(comments[nextIndex].id, anchor: .top)
        previousScrollTarget = topVisibleCommentId
      }
    }
  }
}
