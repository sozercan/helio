//
//  subscribe.swift
//  Helio
//
//  Created by Igor Marcossi on 19/07/23.
//

import Alamofire
import Foundation

extension RedditAPI {
  struct SubscribePayload: Codable {
    var action: SubscribeAction
    var action_source = "o"
    var skip_initial_defaults = false
    var sr: String
    var raw_json = 1
  }

  enum SubscribeAction: String, Codable {
    case sub
    case unsub
  }
}
