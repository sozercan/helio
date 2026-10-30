//
//  fetchUser.swift
//  Helio
//
//  Created by Igor Marcossi on 28/06/23.
//

import Alamofire
import Foundation

extension RedditAPI {
  func fetchUser(_ userName: String) async -> UserData? {
    switch await self.doRequest("\(RedditAPI.redditApiURLBase)/user/\(userName)/about.json", method: .get, decodable: ListingChild<UserData>.self) {
    case let .success(data):
      return data.data
    case let .failure(error):
      print(error)
      return nil
    }
  }

  func fetchUserPublic(_ userName: String) async -> UserData? {
    switch await self.doRequest("\(RedditAPI.redditWWWApiURLBase)/user/\(userName)/about.json", authenticated: false, method: .get, decodable: ListingChild<Either<EmptyStruct, UserData>>.self) {
    case let .success(data):
      switch data.data {
      case .first:
        return nil
      case let .second(userData):
        return userData
      case .none:
        return nil
      }
    case let .failure(error):
      print(error)
      return nil
    }
  }

  struct EmptyStruct: Codable, Hashable {}
}
