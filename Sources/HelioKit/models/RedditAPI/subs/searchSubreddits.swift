//
//  searchSubreddits.swift
//  Helio
//
//  Created by Igor Marcossi on 10/07/23.
//

import Alamofire
import Foundation

extension RedditAPI {
  func searchSubreddits(_ query: String) async -> [SubredditData]? {
    let params = SearchSubredditPayload(q: query)
    switch await self.doRequest("\(RedditAPI.redditApiURLBase)/subreddits/search", method: .get, params: params, paramsLocation: .queryString, decodable: Listing<SubredditData>.self) {
    case let .success(data):
      return data.data?.children?.compactMap(\.data)
    case let .failure(error):
      print(error)
      return nil
    }
  }

  struct SearchSubredditPayload: Codable {
    var count = 10
    var limit = 25
    var show = "all"
    var q: String
    var search_query_id = UUID().uuidString
    var typeahead_active = true
    var sr_detail = true
    var sort = "relevance"
    var raw_json = 1
  }
}
