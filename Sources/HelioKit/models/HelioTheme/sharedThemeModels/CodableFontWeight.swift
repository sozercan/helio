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
    }
  }
}
