//
//  touchScrollIndicators.swift
//  Helio
//

import SwiftUI

extension View {
  /// Scroll indicators set to `visibility` on iPhone and iPad, where scrolling is by touch. On
  /// Mac they're the system's, which follow the "Show scroll bars" setting: a pointer user may
  /// rely on them to see where they are, or drag them.
  func touchScrollIndicators(_ visibility: ScrollIndicatorVisibility) -> some View {
    #if targetEnvironment(macCatalyst)
      scrollIndicators(.automatic)
    #else
      scrollIndicators(visibility)
    #endif
  }
}
