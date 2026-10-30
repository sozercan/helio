//
//  fetchMultiInfo.swift
//  Helio
//
//  Created by Igor Marcossi on 20/08/23.
//

import Alamofire
import Foundation

extension RedditAPI {
  func fetchMultiInfo(_ url: String) async -> MultiData? {
    switch await self.doRequest("\(RedditAPI.redditApiURLBase)/api/multi\(url)", method: .get, decodable: MultiContainerResponse.self) {
    case let .success(data):
      data.data
    case .failure:
      //        print(error)
      nil
    }
  }
}
