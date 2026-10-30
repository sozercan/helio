//
//  searchUsers.swift
//  Helio
//
//  Created by Igor Marcossi on 11/07/23.
//

import Alamofire
import Foundation

extension RedditAPI {
  func searchUsers(_ query: String) async -> [UserData]? {
    let params = SearchUserPayload(q: query)
    switch await self.doRequest("\(RedditAPI.redditApiURLBase)/users/search", method: .get, params: params, paramsLocation: .queryString, decodable: Listing<Either<UserData, BannedUser>>.self) {
    case let .success(data):
      var result: [UserData] = []
      data.data?.children?.forEach { x in
        switch x.data {
        case let .first(el):
          result.append(el)
        case .second:
          break
        case .none:
          break
        }
      }
      return result
    case let .failure(error):
      print(error)
      return nil
    }
  }

  struct BannedUser: Codable, Hashable {
    let is_suspended: Bool?
    let is_blocked: Bool?
    let name: String?
  }

  struct SearchUserPayload: Codable {
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
