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
  var post: Post
  var subreddit: Subreddit
  var ignoreSpecificComment: Bool
  var highlightID: String?
  var sort: CommentSortOption
  var proxy: ScrollViewProxy
  var geometryReader: GeometryProxy
  @Environment(\.useTheme) private var selectedTheme

  // MARK: Properties related to comment skipper

  @Binding var topVisibleCommentId: String?
  @Binding var previousScrollTarget: String?
  @Binding var comments: [Comment]

  @State private var seenComments: String?
  @State private var loading = true
  @Environment(\.globalLoaderDismiss) private var globalLoaderDismiss

  /// `usePrefetch`: take the request `PostView` started when the post opened, if it asked for the
  /// same comments.
  func asyncFetch(_ full: Bool, _ altIgnoreSpecificComment: Bool? = nil, usePrefetch: Bool = false) async {
    let commentID = (altIgnoreSpecificComment ?? ignoreSpecificComment) ? nil : highlightID
    let (request, prefetched) = await MainActor.run {
      (commentsLoad.begin(), usePrefetch ? commentsLoad.takePrefetch(sort: sort, commentID: commentID) : nil)
    }
    let result = if let prefetched {
      await prefetched.value
    } else {
      await post.refreshPost(commentID: commentID, sort: sort, after: nil, subreddit: subreddit.data?.display_name ?? subreddit.id, full: full)
    }
    if let result, let newComments = result.0 {
      newComments.forEach { $0.parentHelio = comments }
      await MainActor.run {
        loading = false
        // A later request (another sort) replaces these.
        guard commentsLoad.isCurrent(request) else { return }
        Task(priority: .utility) {
          _ = await RedditAPI.shared.updateCommentsWithAvatar(comments: newComments, avatarSize: selectedTheme.comments.theme.badge.avatar.size)
        }
        // Not animated: an animated insert makes the list build and measure every new row in
        // one long frame.
        comments = newComments

        if var specificID = highlightID {
          specificID = specificID.hasPrefix("t1_") ? String(specificID.dropFirst(3)) : specificID
          if let rowID = CommentTree.rows(for: newComments).first(where: { $0.comment.data?.id == specificID })?.id {
            doThisAfter(0.1) {
              withAnimation(spring) {
                proxy.scrollTo(rowID, anchor: .center)
              }
            }
          }
        }
      }
    } else {
      await MainActor.run {
        withAnimation {
          loading = false
        }
      }
    }
  }

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
            .onChange(of: ignoreSpecificComment) { _, val in
              Task(priority: .userInitiated) {
                await asyncFetch(post.data == nil, val)
                globalLoaderDismiss()
              }
              if val {
                withAnimation(spring) {
                  proxy.scrollTo("post-content", anchor: .bottom)
                }
              }
            }
            .id("on-change-spacer")
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
      }

      if loading {
        ProgressView()
          .progressViewStyle(.circular)
          .frame(maxWidth: .infinity, minHeight: 100)
          .listRowBackground(Color.clear)
          .onAppear {
            if comments.isEmpty || post.data == nil {
              Task(priority: .userInitiated) {
                await asyncFetch(post.data == nil, usePrefetch: true)
              }
            } else {
              // Only a fetch clears `loading`, so without one the spinner would stay forever.
              withAnimation { loading = false }
            }
            withAnimation { seenComments = post.helioData?.seenComments }
          }
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
