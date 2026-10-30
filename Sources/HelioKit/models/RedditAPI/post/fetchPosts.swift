//
//  fetchPosts.swift
//  Helio
//
//  Created by Igor Marcossi on 25/07/23.
//

import Alamofire
import Foundation

extension RedditAPI {
  func fetchPosts(postFullnames: [String]) async -> [PostData]? {
    let params = FetchPostsPayload(id: postFullnames.joined(separator: ","))
    switch await self.doRequest("\(RedditAPI.redditApiURLBase)/api/info", method: .get, params: params, paramsLocation: .queryString, decodable: Listing<PostData>.self) {
    case let .success(data):
      return data.data?.children?.compactMap(\.data)
    case let .failure(error):
      print(error)
      return nil
    }
  }

  //  typealias FetchPostCommentsResponse = [Either<Listing<PostData>, Listing<CommentData>>?]

  struct FetchPostsPayload: Codable {
    var id: String
    var raw_json = 1
  }
}
