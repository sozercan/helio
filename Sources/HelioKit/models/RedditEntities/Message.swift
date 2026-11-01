//
//  Message.swift
//  Helio
//
//  Created by Igor Marcossi on 10/07/23.
//

import Foundation
import SwiftUI

typealias Message = GenericRedditEntity<MessageData, AnyHashable>

extension Message {
  convenience init(data: T) {
    self.init(data: data, typePrefix: "t1_")
  }

  func toggleRead() async -> Bool {
    if let fullname = data?.name {
      let old = data?.new ?? false
      await MainActor.run {
        withAnimation {
          data?.new = !old
        }
      }
      let result = await old ? ((RedditAPI.shared.readMessage(fullname)) ?? false) : ((RedditAPI.shared.unreadMessage(fullname)) ?? false)
      if !result {
        await MainActor.run {
          withAnimation {
            data?.new = old
          }
        }
      }
      return result
    }
    return false
  }
}

struct MessageData: GenericRedditEntityDataType {
  ///    let first_message: String?
  ///    let first_message_name: String?
  let subreddit: String?
//    let likes: Bool?
//    let replies: Either<String, Listing<CommentData>>?
  let author_fullname: String?
  let id: String
  let subject: String?
//    let associated_awarding_id: String?
//    let score: Int?
  let author: String?
  let author_flair_text: String?
//    let num_comments: Int?
  let parent_id: String?
  let subreddit_name_prefixed: String?
  var new: Bool?
  let type: String?
  let body: String?
  let link_title: String?
  let dest: String?
  let was_comment: Bool?
  let body_html: String?
  let name: String?
  let created: Double?
  let created_utc: Double?
  let context: String?
//    let distinguished: String?
}

extension MessageData {
  /// The comment a reply or mention is about, opened in its post. Nil for private messages,
  /// which aren't about a post, and when the message's link has no post id.
  var commentDestination: Router.NavDest? {
    guard let subreddit, let context, let postID = getPostId(from: context) else { return nil }
    let post = Post(id: postID, subID: subreddit)
    // Replies to a post highlight the reply itself; replies to a comment, the comment.
    let parentComment = parent_id.flatMap { $0.hasPrefix("t3_") ? nil : $0 }
    if let highlightID = parentComment ?? name {
      return .reddit(.postHighlighted(post, highlightID))
    }
    return .reddit(.post(post))
  }
}

/// The post id in a comment's permalink, such as `/r/apple/comments/abc123/title/def456/?context=3`.
func getPostId(from urlString: String) -> String? {
  let path = urlString.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
  let parts = path.split(separator: "/")
  guard let comments = parts.firstIndex(of: "comments"), comments + 1 < parts.count else { return nil }
  return String(parts[comments + 1])
}
