//
//  blurTransitions.swift
//  Helio
//
//  Created by Igor Marcossi on 29/06/23.
//

import Foundation
import SwiftUI

struct BlurAndFadeEffect: ViewModifier {
  let isActive: Bool

  func body(content: Content) -> some View {
    content
      .opacity(isActive ? 1 : 0)
      .blur(radius: isActive ? 0 : 12)
  }
}

struct ScaleAndBlurEffect: ViewModifier {
  let isActive: Bool

  func body(content: Content) -> some View {
    content
      .scaleEffect(isActive ? 1 : 0.75)
      .opacity(isActive ? 1 : 0)
      .blur(radius: isActive ? 0 : 30)
      .zIndex(isActive ? 0 : -1)
  }
}

extension AnyTransition {
  static var scaleAndBlur: AnyTransition {
    .modifier(
      active: ScaleAndBlurEffect(isActive: false),
      identity: ScaleAndBlurEffect(isActive: true),
    )
  }

  static var fadeBlur: AnyTransition {
    .modifier(
      active: BlurAndFadeEffect(isActive: false),
      identity: BlurAndFadeEffect(isActive: true),
    )
  }
}
