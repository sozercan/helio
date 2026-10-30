//
//  RedditMediaPost.swift
//  Helio
//
//  Created by Igor Marcossi on 31/07/23.
//

import Combine
import SwiftUI

struct RedditMediaPost: View {
  var entity: RedditEntityType
  static let height: CGFloat = 88

  var body: some View {
    HStack(spacing: 16) {
      switch entity {
      case let .comment(comment):
        //            ShortCommentPostLink(comment: comment)
        if let commentHelioData = comment.helioData {
          CommentLink(showReplies: false, comment: comment, commentHelioData: commentHelioData, children: comment.childrenHelio)
            .padding(.vertical, 8)
        }
      case let .post(post):
        ShortPostLink(noHPad: true, post: post)
      case let .user(user):
        UserLinkContainer(noHPad: true, user: user)
      case let .subreddit(subreddit):
        SubredditLinkContainer(sub: subreddit)
      default:
        EmptyView()
      }
    }
    .frame(maxWidth: .infinity, minHeight: RedditMediaPost.height, maxHeight: RedditMediaPost.height)
    .padding(.horizontal, 8)
    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.primary.opacity(0.1)))
  }
}
