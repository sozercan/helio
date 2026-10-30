//
//  Scacity.swift
//  Helio
//
//  Created by Igor Marcossi on 16/12/23.
//

import SwiftUI

public extension AnyTransition {
  static var scacity: AnyTransition = .scale.combined(with: .opacity)
}
