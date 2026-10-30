//
//  increaseHitboxBy.swift
//  Helio
//
//  Created by Igor Marcossi on 28/12/23.
//

import SwiftUI

extension View {
  func increaseHitboxBy(_ amount: Double, shape: some Shape = Rectangle(), disable: Bool = false) -> some View {
    self.background(GeometryReader { Color.hitbox.frame($0.size * (disable ? 1 : amount)).contentShape(shape) })
  }

  func increaseHitboxOf(_ size: CGSize, by: Double, shape: some Shape = Rectangle(), disable: Bool = false) -> some View {
    self.background(Color.hitbox.frame(size * (disable ? 1 : by)).contentShape(shape))
  }

  func increaseHitboxOf(_ size: Double, by: Double, shape: some Shape = Rectangle(), disable: Bool = false) -> some View {
    self.background(Color.hitbox.frame(size * (disable ? 1 : by)).contentShape(shape))
  }
}
