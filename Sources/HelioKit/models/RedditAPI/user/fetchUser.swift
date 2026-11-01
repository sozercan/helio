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
}
