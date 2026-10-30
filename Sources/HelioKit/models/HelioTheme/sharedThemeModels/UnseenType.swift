//
//  UnseenType.swift
//  Helio
//
//  Created by Igor Marcossi on 21/11/23.
//

import Foundation

enum UnseenType: Codable, Hashable, Equatable {
  case dot(ColorSchemes<ThemeColor>), fade

  func isEqual(_ to: UnseenType) -> Bool {
    if case .dot = self {
      switch to {
      case .dot:
        true
      case .fade:
        false
      }
    } else {
      switch to {
      case .dot:
        false
      case .fade:
        true
      }
    }
  }
}
