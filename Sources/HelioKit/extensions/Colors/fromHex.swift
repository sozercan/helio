//
//  fromHex.swift
//  Helio
//
//  Created by Igor Marcossi on 27/06/23.
//

import Foundation
import SwiftUI
import UIKit

extension UIColor {
  convenience init(hex: String, alpha: Double = 1) {
    let trimHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    let dropHash = String(trimHex.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
    let hexString = trimHex.starts(with: "#") ? dropHash : trimHex
    let ui64 = UInt64(hexString, radix: 16)
    let value = ui64 != nil ? Int(ui64!) : 0
    // #RRGGBB
    var components = (
      R: CGFloat((value >> 16) & 0xFF) / 255,
      G: CGFloat((value >> 08) & 0xFF) / 255,
      B: CGFloat((value >> 00) & 0xFF) / 255,
      a: CGFloat(alpha),
    )
    if String(hexString).count == 8 {
      // #RRGGBBAA
      components = (
        R: CGFloat((value >> 24) & 0xFF) / 255,
        G: CGFloat((value >> 16) & 0xFF) / 255,
        B: CGFloat((value >> 08) & 0xFF) / 255,
        a: CGFloat((value >> 00) & 0xFF) / 255,
      )
    }
    self.init(red: components.R, green: components.G, blue: components.B, alpha: components.a)
  }
}

extension UIColor {
  var alpha: CGFloat {
    var alpha: CGFloat = 0
    getRed(nil, green: nil, blue: nil, alpha: &alpha)
    return alpha
  }
}

extension Color {
  static func hex(_ h: String) -> Color {
    var hex = h
    if h.hasPrefix("#") {
      hex.removeFirst(1)
    }
    return Color(UIColor(hex: hex))
  }

  var alpha: CGFloat {
    UIColor(self).alpha
  }

  var hex: String {
    let uiColor = UIColor(self)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
      return "000000"
    }
    let rgb = Int(red * 255) << 16 | Int(green * 255) << 8 | Int(blue * 255) << 0
    return String(format: "%06x", rgb)
  }
}
