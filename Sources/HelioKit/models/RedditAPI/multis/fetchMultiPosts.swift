//
//  fetchMultiPosts.swift
//  Helio
//
//  Created by Igor Marcossi on 20/08/23.
//

import Alamofire
import Defaults
import Foundation

extension RedditAPI {
  func fetchMultiPosts(path: String, sort: SubListingSortOption = .best, after: String? = nil, limit: Int = Defaults[.SubredditFeedDefSettings].chunkLoadSize, altCredential: RedditCredential? = nil) async -> ([ListingChild<PostData>]?, String?)? {
    let params = FetchSubsPayload(limit: limit, after: after)
    let base = path.hasSuffix("/") ? String(path.dropLast()) : path
    // Best is a front page and subreddit sort; a multi's bare listing is its default order.
    let endpoint = sort == .best ? "\(base).json" : "\(base)/\(Self.listingEndpoint(sort))"
    switch await self.doRequest("\(RedditAPI.redditApiURLBase)\(endpoint)", method: .get, params: params, paramsLocation: .queryString, decodable: Listing<PostData>.self, altCredential: altCredential) {
    case let .success(data):
      return (data.data?.children, data.data?.after)
    case let .failure(error):
      print(error)
      return nil
    }
  }
}
