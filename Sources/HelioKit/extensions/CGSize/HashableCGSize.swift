//
//  hashableCGSize.swift
//  Helio
//
//  Created by Igor Marcossi on 21/09/23.
//

import Foundation
import SwiftUI

extension CGSize: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(width)
    hasher.combine(height)
  }
  
//    public var hashValue: Int {
//        return NSCoder.string(for: self).hashValue
//    }
}
