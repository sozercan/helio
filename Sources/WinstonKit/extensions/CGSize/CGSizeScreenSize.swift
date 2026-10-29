//
//  CGSizeScreenSize.swift
//  winston
//
//  Created by Igor Marcossi on 31/12/23.
//

import Foundation

extension CGSize {
  /// The current window's size (see `WindowMetrics`).
  static var screenSize: CGSize { WindowMetrics.shared.size }
}
