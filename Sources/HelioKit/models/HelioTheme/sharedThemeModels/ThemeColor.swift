//
//  ThemeColor.swift
//  Helio
//
//  Created by Igor Marcossi on 23/01/24.
//

import Foundation
import SwiftUI

/// Locked: colors are resolved off the main thread too, e.g. while posts are built in
/// parallel (Post.initMultiple), and unsynchronized dictionary writes can crash.
final class ThemeColorsCache: @unchecked Sendable {
  static let shared = ThemeColorsCache()
  private let lock = NSLock()
  private var colors: [ThemeColor:Color] = [:]
  private var uiColors: [ThemeColor:UIColor] = [:]
  private init() {}

  func color(_ key: ThemeColor, make: () -> Color) -> Color {
    lock.withLock {
      if let color = colors[key] { return color }
      let color = make()
      colors[key] = color
      return color
    }
  }

  func uiColor(_ key: ThemeColor, make: () -> UIColor) -> UIColor {
    lock.withLock {
      if let uiColor = uiColors[key] { return uiColor }
      let uiColor = make()
      uiColors[key] = uiColor
      return uiColor
    }
  }
}

struct ThemeColor: Codable, Hashable, Equatable, Identifiable {
  var id: String { "\(self.hex)\(self.alpha)" }
  var hex: String
  var alpha: CGFloat = 1.0
  
  func color() -> Color {
    ThemeColorsCache.shared.color(self) { Color(uiColor: UIColor(hex: hex, alpha: alpha)) }
  }
  
  func uiColor() -> UIColor {
    ThemeColorsCache.shared.uiColor(self) { UIColor(hex: hex, alpha: Double(alpha)) }
  }
}
