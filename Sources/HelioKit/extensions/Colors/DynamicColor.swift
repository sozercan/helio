import SwiftUI
import UIKit

extension Color {}

extension UIColor {
  convenience init(light: UIColor, dark: UIColor, highContrastLight: UIColor? = nil, highContrastDark: UIColor? = nil) {
    self.init(dynamicProvider: { traits in
      let highContrast = traits.accessibilityContrast == .high
      switch traits.userInterfaceStyle {
      case .light, .unspecified:
        return highContrast ? highContrastLight ?? light : light

      case .dark:
        return highContrast ? highContrastDark ?? dark : dark

      @unknown default:
        assertionFailure("Unknown userInterfaceStyle: \(traits.userInterfaceStyle)")
        return light
      }
    })
  }
}
