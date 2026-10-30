//
//  MixedContentLink.swift
//  Helio
//
//  Created by Igor Marcossi on 21/11/23.
//

import Defaults
import SwiftUI

struct MixedContentLink: View, Equatable {
  static func == (lhs: MixedContentLink, rhs: MixedContentLink) -> Bool {
    lhs.content == rhs.content && lhs.theme == rhs.theme
  }

  var content: Either<Post, Comment>
  var theme: SubPostsListTheme

  @Default(.PostLinkDefSettings) private var postLinkDefSettings
  @Default(.CommentLinkDefSettings) private var commentLinkDefSettings
  @Environment(\.contentWidth) private var contentWidth

  var body: some View {
    switch content {
    case let .first(post):
      if let helioData = post.helioData, let postSub = helioData.subreddit {
        PostLink(id: post.id, theme: theme, showSub: true, compactPerSubreddit: nil, contentWidth: contentWidth, defSettings: postLinkDefSettings)
          .environment(\.contextPost, post)
          .environment(\.contextSubreddit, postSub)
          .environment(\.contextPostHelioData, helioData)
      }
    case let .second(comment):
      VStack {
        ShortCommentPostLink(comment: comment)
          .padding()
        if let commentHelioData = comment.helioData {
          CommentLink(showReplies: false, comment: comment, commentHelioData: commentHelioData, children: comment.childrenHelio)
        }
      }
      .background(PostLinkBG(theme: theme.theme, stickied: false, secondary: false))
      .mask(RR(theme.theme.cornerRadius, Color.black))
    }
  }
}
