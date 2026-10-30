//
//  fetchSub.swift
//  Helio
//
//  Created by Igor Marcossi on 30/06/23.
//

import Alamofire
import Foundation

extension RedditAPI {
  func fetchSub(_ name: String) async -> ListingChild<SubredditData>? {
    switch await self.doRequest("\(RedditAPI.redditApiURLBase)\(name.hasPrefix("/r/") ? name : "/r/\(name)/")about.json?raw_json=1", method: .get, decodable: ListingChild<SubredditData>.self) {
    case let .success(data):
      return data
    case let .failure(error):
      print(error)
      return nil
    }
  }
}
