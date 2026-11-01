//
//  increaseHitboxBy.swift
//  Helio
//
//  Created by Igor Marcossi on 28/12/23.
//

import SwiftUI

extension View {
  func increaseHitboxOf(_ size: Double, by: Double, shape: some Shape = Rectangle(), disable: Bool = false) -> some View {
    self.background(Color.hitbox.frame(size * (disable ? 1 : by)).contentShape(shape))
  }
}
