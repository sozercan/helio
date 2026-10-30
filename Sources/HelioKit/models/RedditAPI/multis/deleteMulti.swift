//
//  deleteMulti.swift
//  Helio
//
//  Created by Igor Marcossi on 20/08/23.
//

import Alamofire
import Foundation

extension RedditAPI {
  func deleteMulti(_ path: String) async -> Bool? {
    switch await self.doRequest("\(RedditAPI.redditApiURLBase)/api/multi/\(path)", method: .delete) {
    case .success:
      true
    case .failure:
      //        print(error)
      nil
    }
  }
}
