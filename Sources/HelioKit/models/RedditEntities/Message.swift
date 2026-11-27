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
  let subreddit: String?
  let author_fullname: String?
  let id: String
  let subject: String?
  let author: String?
  let author_flair_text: String?
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
}

extension MessageData {
  var commentDestination: Router.NavDest? {
    guard let subreddit, let context, let postID = getPostId(from: context) else { return nil }
    let post = Post(id: postID, subID: subreddit)
    let parentComment = parent_id.flatMap { $0.hasPrefix("t1_") ? $0 : nil }
    let ownComment = name.flatMap { $0.hasPrefix("t1_") ? $0 : nil }
    if let highlightID = parentComment ?? ownComment {
      return .reddit(.postHighlighted(post, highlightID))
    }
    return .reddit(.post(post))
  }
}

func getPostId(from urlString: String) -> String? {
  let path = URLComponents(string: urlString)?.path ?? String(urlString.split(separator: "?").first ?? "")
  let parts = path.split(separator: "/").map(String.init)
  let comments: Int? = switch parts.first {
  case "r", "u", "user": parts.count > 2 && parts[2] == "comments" ? 2 : nil
  case "comments": 0
  default: nil
  }
  guard let comments, comments + 1 < parts.count else { return nil }
  return parts[comments + 1]
}
