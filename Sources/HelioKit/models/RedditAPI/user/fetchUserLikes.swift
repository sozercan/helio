//
//  fetchUserLikes.swift
//  Helio
//

import Foundation

extension RedditAPI {
  /// A post or comment of the account's: its subreddit and the title of its post.
  struct ActivityItem: Sendable {
    let subreddit: String
    let title: String?
    var created: Double?
  }

  /// The account's latest upvoted posts, newest first. Reddit keeps this private to the account.
  func fetchUpvotedPosts(_ userName: String, limit: Int = 100, altCredential: RedditCredential? = nil) async -> [PostData]? {
    let params = FetchSubsPayload(limit: limit)
    switch await doRequest("\(RedditAPI.redditApiURLBase)/user/\(userName)/upvoted.json", method: .get, params: params, paramsLocation: .queryString, decodable: Listing<PostData>.self, altCredential: altCredential) {
    case let .success(listing):
      return listing.data?.children?.compactMap(\.data) ?? []
    case let .failure(error):
      forYouLogger.error("Couldn't load upvoted posts: \(String(describing: error), privacy: .private)")
      return nil
    }
  }

  /// The account's latest saved posts and comments, newest first.
  func fetchSavedItems(_ userName: String, limit: Int = 100, altCredential: RedditCredential? = nil) async -> [ActivityItem]? {
    let params = FetchSubsPayload(limit: limit)
    switch await doRequest("\(RedditAPI.redditApiURLBase)/user/\(userName)/saved.json", method: .get, params: params, paramsLocation: .queryString, decodable: Listing<Either<PostData, CommentData>>.self, altCredential: altCredential) {
    case let .success(listing):
      return listing.data?.children?.compactMap(\.data).compactMap(Self.activityItem) ?? []
    case let .failure(error):
      forYouLogger.error("Couldn't load saved items: \(String(describing: error), privacy: .private)")
      return nil
    }
  }

  /// The account's latest comments and posts, newest first. nil when neither loads.
  func fetchParticipation(_ userName: String, limit: Int = 100, altCredential: RedditCredential? = nil) async -> [ActivityItem]? {
    async let comments = fetchUserOverview(userName, "comments", nil, limit: limit, altCredential: altCredential)
    async let posts = fetchUserOverview(userName, "posts", nil, limit: limit, altCredential: altCredential)
    let lists = await [comments, posts]
    guard lists.contains(where: { $0 != nil }) else { return nil }
    let items = lists.compactMap { $0?.0 }.flatMap(\.self).compactMap(Self.activityItem)
    return items.sorted { ($0.created ?? 0) > ($1.created ?? 0) }
  }

  private static func activityItem(_ item: Either<PostData, CommentData>) -> ActivityItem? {
    switch item {
    case let .first(post): ActivityItem(subreddit: post.subreddit, title: post.title, created: post.created_utc ?? post.created)
    case let .second(comment): comment.subreddit.map { ActivityItem(subreddit: $0, title: comment.link_title, created: comment.created_utc ?? comment.created) }
    }
  }
}
