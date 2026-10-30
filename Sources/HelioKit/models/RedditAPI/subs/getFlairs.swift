//
//  getFlairs.swift
//  Helio
//
//  Created by Igor Marcossi on 27/07/23.
//

import Alamofire
import Defaults
import Foundation
import UIKit

extension RedditAPI {
  func getFlairs(_ subName: String) async -> [Flair]? {
    switch await self.doRequest("\(RedditAPI.redditApiURLBase)/r/\(subName)/api/link_flair_v2?raw_json=1", method: .get, decodable: [Flair].self) {
    case let .success(data):
      data
    case .failure:
      nil
    }
  }
}

struct Flair: GenericRedditEntityDataType, Identifiable, Defaults.Serializable {
  let type: String?
  let text_editable: Bool?
  let allowable_content: String?
  let text: String
  let max_emojis: Int?
  let text_color: String?
  let mod_only: Bool?
  let css_class: String?
  let background_color: String?
  let id: String
}
