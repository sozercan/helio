//
//  defaults.swift
//  Helio
//
//  Created by Igor Marcossi on 26/06/23.
//

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

  /* <Heavy Defaults are kept separated, these should be in CoreData or something> */
  static let filteredSubreddits = Key<[String]>("filteredSubreddits", default: [])
  static let likedButNotSubbed = Key<[Subreddit]>("likedButNotSubbed", default: [])
  /// Subreddits For You no longer suggests ("Not interested").
  static let forYouDismissedSubs = Key<[String]>("forYouDismissedSubs", default: [])
  /// Set once For You loads, from when the posts opened are kept for it (`ForYouHistory`).
  static let forYouUsed = Key<Bool>("forYouUsed", default: false)
  /// The posts each account opened, by credential id, newest first (`ForYouHistory`).
  static let forYouOpenedPosts = Key<[String: [ForYouOpenedPost]]>("forYouOpenedPosts", default: [:])
  /* </Heavy Defaults are kept separated, these should be in CoreData or something> */

  /// Steps content text is moved from the system text size (Settings > Appearance > Text Size).
  /// Its own key: a new field in an existing settings struct would fail to decode stored values.
  static let contentTextSizeAdjustment = Key<Int>("contentTextSizeAdjustment", default: 0)

  /// Subreddits whose feed is a canvas of thumbnails (`PostLayout.canvas`), by subreddit id.
  static let canvasSubreddits = Key<Set<String>>("canvasSubreddits", default: [])

  /// When each account's subscriptions and multis were last synced at launch, by credential id
  /// and user name.
  static let subsSyncedAt = Key<[String: Date]>("subsSyncedAt", default: [:])
}
