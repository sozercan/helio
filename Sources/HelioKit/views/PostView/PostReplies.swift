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
  /// Told which rows show, for where the page goes back to after the layout changes.
  var session: PostSession
  var retry: () -> Void = {}

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
            .onAppear { session.rowShown(row.id) }
            .onDisappear { session.rowHidden(row.id) }
        }
        .transaction { transaction in
          // SwiftUI `List` animates simultaneous row height changes and multi-row deletions with
          // a noticeable scroll jump; keep comment collapse/expand crisp without List row jitter.
          transaction.animation = nil
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
      } else if commentsLoad.failed, comments.isEmpty {
        VStack(spacing: 12) {
          if let limitedUntil = RedditRateLimit.shared.limitedUntil(account: RedditAPI.accountID(nil), authorization: RedditAPI.accountAuthorization(nil)) {
            Text(RedditRateLimit.retryText(until: limitedUntil))
              .multilineTextAlignment(.center)
          } else {
            Text("Couldn't load comments")
          }
          Button("Try again", systemImage: "arrow.clockwise", action: retry)
            .buttonStyle(.actionSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .compositingGroup()
        .opacity(0.6)
        .listRowBackground(Color.clear)
        .id("comments-load-error")
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
