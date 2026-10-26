//
//  screenSize.swift
//  winston
//
//  Created by Igor Marcossi on 07/12/23.
//

import Foundation
import UIKit

// The current window's size, not the screen's: the window can be resized (iPhone Duo,
// iPad multitasking, Mac). Reading these in a view's body re-renders it when the size changes.
extension Double {
  static var screenW: Double { WindowMetrics.shared.size.width }
  static var screenH: Double { WindowMetrics.shared.size.height }
  static var screenScale: Double { WindowMetrics.shared.displayScale }
}

extension CGFloat {
  static var screenW: CGFloat { WindowMetrics.shared.size.width }
  static var screenH: CGFloat { WindowMetrics.shared.size.height }
  static var screenScale: CGFloat { WindowMetrics.shared.displayScale }
}
