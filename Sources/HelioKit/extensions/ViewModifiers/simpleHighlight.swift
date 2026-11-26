import SwiftUI

extension View {
  func simpleHighlight(_ pressed: Bool, opacity: Double = 0.1) -> some View {
    self
      .overlay { Color.primary.opacity(pressed ? opacity : 0).allowsHitTesting(false) }
  }
}
