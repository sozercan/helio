//
//  fetchUserLikes.swift
//  Helio
//

import Foundation

extension RedditAPI {
  /// A saved post's or comment's subreddit, and the title of its post.
  struct SavedItem: Sendable {
    let subreddit: String
    let title: String?
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
  func fetchSavedItems(_ userName: String, limit: Int = 100, altCredential: RedditCredential? = nil) async -> [SavedItem]? {
    let params = FetchSubsPayload(limit: limit)
    switch await doRequest("\(RedditAPI.redditApiURLBase)/user/\(userName)/saved.json", method: .get, params: params, paramsLocation: .queryString, decodable: Listing<Either<PostData, CommentData>>.self, altCredential: altCredential) {
    case let .success(listing):
      return listing.data?.children?.compactMap(\.data).compactMap { item in
        switch item {
        case let .first(post): SavedItem(subreddit: post.subreddit, title: post.title)
        case let .second(comment): comment.subreddit.map { SavedItem(subreddit: $0, title: comment.link_title) }
        }
      } ?? []
    case let .failure(error):
      forYouLogger.error("Couldn't load saved items: \(String(describing: error), privacy: .private)")
      return nil
    }
  }
}
