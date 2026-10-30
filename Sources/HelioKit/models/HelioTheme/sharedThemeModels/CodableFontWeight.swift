//
//  CodableFontWeight.swift
//  Helio
//
//  Created by Igor Marcossi on 21/11/23.
//

import Foundation
import SwiftUI

enum CodableFontWeight: Codable, Hashable, CaseIterable, Equatable {
  case light, regular, medium, semibold, bold

  var t: Font.Weight {
    switch self {
    case .light:
      .light
    case .regular:
      .regular
    case .medium:
      .medium
    case .semibold:
      .semibold
    case .bold:
      .bold
//    case .heavy:
//      return .heavy
//    case .black:
//      return .black
    }
  }

  var ut: UIFont.Weight {
    switch self {
    case .light:
      .light
    case .regular:
      .regular
    case .medium:
      .medium
    case .semibold:
      .semibold
    case .bold:
      .bold
//    case .heavy:
//      return .heavy
//    case .black:
//      return .black
    }
  }
}
