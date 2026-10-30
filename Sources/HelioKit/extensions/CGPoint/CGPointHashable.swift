//
//  CGPointHashable.swift
//  Helio
//
//  Created by Igor Marcossi on 27/11/23.
//

import CoreGraphics
import Foundation

extension CGPoint: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(x)
    hasher.combine(y)
  }
}
