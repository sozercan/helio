//
//  favorite.swift
//  Helio
//
//  Created by Igor Marcossi on 19/07/23.
//

import Alamofire
import Foundation

extension RedditAPI {
  struct FavoritePayload: Codable {
    var make_favorite: Bool
    var sr_name: String
    var raw_json = 1
  }
}
