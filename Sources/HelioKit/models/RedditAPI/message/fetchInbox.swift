//
//  fetchInbox.swift
//  Helio
//
//  Created by Igor Marcossi on 10/07/23.
//

import Alamofire
import Foundation

extension RedditAPI {
  func fetchInbox(after: String = "", limit: Int) async -> ([MessageData]?, String?)? {
    let params = FetchInboxPayload(after: after, limit: limit)
    switch await self.doRequest("\(RedditAPI.redditApiURLBase)/message/inbox.json", method: .get, params: params, paramsLocation: .queryString, decodable: Listing<MessageData>.self) {
    case let .success(data):
      return (data.data?.children?.map(\.data).compactMap(\.self), data.data?.after)
    case let .failure(error):
      print(error)
      return nil
    }
  }

  struct FetchInboxPayload: Codable {
    var mark = "true"
    var count = 0
    var after = ""
    var before = ""
    var limit = 25
    var show = "all"
    var sr_detail = 1
    var raw_json = 1
  }
}
