//
//  fetchMe.swift
//  Helio
//
//  Created by Igor Marcossi on 01/07/23.
//

import Alamofire
import Foundation

extension RedditAPI {
  func fetchMe(force: Bool = false, altCredential: RedditCredential? = nil, saveToken: Bool = true) async -> UserData? {
    if !force, let me {
      await MainActor.run {
        RedditAPI.shared.me = me
      }
    } else {
      switch await self.doRequest("\(RedditAPI.redditApiURLBase)/api/v1/me", method: .get, decodable: UserData.self, altCredential: altCredential, saveToken: saveToken) {
      case let .success(data):
        await MainActor.run {
          RedditAPI.shared.me = User(data: data)
        }
        return data
      case let .failure(error):
        print(error)
        await MainActor.run {
          RedditAPI.shared.me = nil
        }
        return nil
      }
    }
    return nil
  }
}
