//
//  DynamicColor.swift
//  Helio
//
//  Created by Igor Marcossi on 14/12/23.
//

import SwiftUI
import UIKit

extension Color {}

extension UIColor {
  convenience init(light: UIColor, dark: UIColor) {
    self.init(dynamicProvider: { traits in
      switch traits.userInterfaceStyle {
      case .light, .unspecified:
        return light

      case .dark:
        return dark

      @unknown default:
        assertionFailure("Unknown userInterfaceStyle: \(traits.userInterfaceStyle)")
        return light
      }
    })
  }
}
