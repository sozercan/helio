//
//  ShortCommentPostLink.swift
//  Helio
//
//  Created by Igor Marcossi on 04/07/23.
//

import Defaults
import SwiftUI

struct ShortCommentPostLink: View {
  var comment: Comment
  @State var openedPost = false
  @State var openedSub = false
  var body: some View {
    if let data = comment.data, let _ = data.link_id, let _ = data.subreddit {
      VStack(alignment: .leading, spacing: 6) {
        if let subreddit = data.subreddit {
          Text(data.link_title ?? "Error").font(.system(size: MacIdiom.size(15))).foregroundStyle(Color.primary.opacity(0.75)) +
            Text(" · ").font(.system(size: MacIdiom.size(13))).foregroundStyle(Color.primary.opacity(0.5)) +
            Text("r/\(subreddit)").italic().font(.system(size: MacIdiom.size(14))).foregroundStyle(Color.primary.opacity(0.75))
        }
      }
      .multilineTextAlignment(.leading)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RR(14, Color.secondary.opacity(0.075)),
      )
      .foregroundColor(.primary)
      .multilineTextAlignment(.leading)
    } else {
      Text("Oops")
    }
  }
}
