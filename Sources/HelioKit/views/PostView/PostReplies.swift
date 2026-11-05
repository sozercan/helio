//
//  PostReplies.swift
//  Helio
//
//  Created by Igor Marcossi on 31/07/23.
//

import Defaults
import SwiftUI

struct PostReplies: View {
  var commentsLoad: CommentsLoad
  /// The comments seen before this visit, so the new ones stand out.
  var seenComments: String?
  var post: Post
  var subreddit: Subreddit
  var ignoreSpecificComment: Bool
  var highlightID: String?
  var sort: CommentSortOption
  var proxy: ScrollViewProxy
  @Environment(\.useTheme) private var selectedTheme

  // MARK: Properties related to comment skipper

  @Binding var topVisibleCommentId: String?
  @Binding var previousScrollTarget: String?
  @Binding var comments: [Comment]

  var body: some View {
    let theme = selectedTheme.comments
    let horPad = theme.theme.outerHPadding
    Group {
      let postFullname = post.data?.name ?? ""
      Group {
        ForEach(CommentTree.rows(for: comments)) { row in
          CommentTreeRowView(row: row, post: post, postFullname: postFullname, highlightID: ignoreSpecificComment ? nil : highlightID, seenComments: seenComments, comments: $comments)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: horPad, bottom: 0, trailing: horPad))
        }
        Section {
          Spacer()
            .frame(height: 1)
            .listRowBackground(Color.clear)
            .id("on-change-spacer")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
      }

      if !commentsLoad.loaded {
        // `PostView` loads the comments.
        ProgressView()
          .progressViewStyle(.circular)
          .frame(maxWidth: .infinity, minHeight: 100)
          .listRowBackground(Color.clear)
          .id("loading-comments")
      } else if comments.isEmpty {
        Text(QuirkyMessageUtil.noCommentsFoundMessage())
          .frame(maxWidth: .infinity, minHeight: 300)
          .opacity(0.25)
          .listRowBackground(Color.clear)
          .multilineTextAlignment(.center)
          .id("no-comments-placeholder")
      }
    }
  }
}
