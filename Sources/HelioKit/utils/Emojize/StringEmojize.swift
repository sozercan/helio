//
//  StringEmojize.swift
//  Helio
//
//  Created by Igor Marcossi on 31/07/23.
//

import Foundation

extension String {
  func emojied() -> String {
    var transformedString = self
    for (key, value) in EMOJI_HASH {
      transformedString = transformedString.replacingOccurrences(of: key, with: value)
    }
    return transformedString
  }
}
