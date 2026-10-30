//
//  rgb.swift
//  Helio
//

import UIKit

extension UIColor {
  // swiftlint:disable:next large_tuple
  var rgb: (CGFloat, CGFloat, CGFloat) {
    var fRed: CGFloat = 0
    var fGreen: CGFloat = 0
    var fBlue: CGFloat = 0
    var fAlpha: CGFloat = 0

    if self.getRed(&fRed, green: &fGreen, blue: &fBlue, alpha: &fAlpha) {
      return (fRed, fGreen, fBlue)
    } else {
      return (0, 0, 0)
    }
  }
}
