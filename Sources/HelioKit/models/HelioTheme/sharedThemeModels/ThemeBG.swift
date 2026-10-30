//
//  ThemeBG.swift
//  Helio
//
//  Created by Igor Marcossi on 21/11/23.
//

import Foundation

enum ThemeBG: Codable, Hashable, Equatable {
  case color(ColorSchemes<ThemeColor>)
  case img(ColorSchemes<String>)

  func isEqual(_ to: ThemeBG) -> Bool {
    if case .color = self {
      switch to {
      case .color:
        true
      case .img:
        false
      }
    } else {
      switch to {
      case .color:
        false
      case .img:
        true
      }
    }
  }
}
