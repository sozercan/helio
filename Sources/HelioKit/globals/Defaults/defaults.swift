import Defaults
import Foundation
import SwiftUI
import UIKit

let DEFAULT_POST_SWIPE_ACTIONS = SwipeActionsSet(
  id: "post-swipe-actions",
  leftFirst: AnySwipeAction(UpvotePostAction()),
  leftSecond: AnySwipeAction(SavePostAction()),
  rightFirst: AnySwipeAction(DownvotePostAction()),
  rightSecond: AnySwipeAction(SeenPostAction()),
)

let DEFAULT_COMMENT_SWIPE_ACTIONS = SwipeActionsSet(
  id: "comment-swipe-actions",
  leftFirst: AnySwipeAction(UpvoteCommentAction()),
  leftSecond: AnySwipeAction(SaveCommentAction()),
  rightFirst: AnySwipeAction(DownvoteCommentAction()),
  rightSecond: AnySwipeAction(ReplyCommentAction()),
)

extension Defaults.Keys {
  static let PostLinkDefSettings = Key<PostLinkDefSettings>("PostLinkDefSettings", default: .init())
  static let VideoDefSettings = Key<VideoDefSettings>("VideoDefSettings", default: .init())
  static let AppearanceDefSettings = Key<AppearanceDefSettings>("AppearanceDefSettings", default: .init())
  static let BehaviorDefSettings = Key<BehaviorDefSettings>("BehaviorDefSettings", default: .init())
  static let GeneralDefSettings = Key<GeneralDefSettings>("GeneralDefSettings", default: .init())
  static let SubredditFeedDefSettings = Key<SubredditFeedDefSettings>("SubredditFeedDefSettings", default: .init())
  static let CommentLinkDefSettings = Key<CommentLinkDefSettings>("CommentLinkDefSettings", default: .init())
  static let CommentsSectionDefSettings = Key<CommentsSectionDefSettings>("CommentsSectionDefSettings", default: .init())
  static let PostPageDefSettings = Key<PostPageDefSettings>("PostPageDefSettings", default: .init())
  static let ThemesDefSettings = Key<ThemesDefSettings>("ThemesDefSettings", default: .init())

  static let contentTextSizeAdjustment = Key<Int>("contentTextSizeAdjustment", default: 0)

  static let canvasSubreddits = Key<Set<String>>("canvasSubreddits", default: [])

  static let subsSyncedAt = Key<[String: Date]>("subsSyncedAt", default: [:])
}
