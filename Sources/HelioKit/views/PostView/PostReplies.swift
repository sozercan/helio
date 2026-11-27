import Defaults
import SwiftUI

struct PostReplies: View {
  var commentsLoad: CommentsLoad
  var seenComments: String?
  var post: Post
  var subreddit: Subreddit
  var ignoreSpecificComment: Bool
  var highlightID: String?
  var sort: CommentSortOption
  var proxy: ScrollViewProxy
  @Environment(\.useTheme) private var selectedTheme

  @Binding var topVisibleCommentId: String?
  @Binding var previousScrollTarget: String?
  @Binding var comments: [Comment]
  var session: PostSession
  var retry: () -> Void = {}

  var body: some View {
    let theme = selectedTheme.comments
    let horPad = theme.theme.outerHPadding
    Group {
      if commentsLoad.loaded, commentsLoad.failed, !comments.isEmpty {
        errorView(minHeight: 80)
      }

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
        ProgressView()
          .progressViewStyle(.circular)
          .frame(maxWidth: .infinity, minHeight: 100)
          .listRowBackground(Color.clear)
          .id("loading-comments")
      } else if commentsLoad.failed, comments.isEmpty {
        errorView(minHeight: 200)
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

  private func errorView(minHeight: CGFloat) -> some View {
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
    .frame(maxWidth: .infinity, minHeight: minHeight)
    .compositingGroup()
    .opacity(0.6)
    .listRowBackground(Color.clear)
    .id("comments-load-error")
  }
}
