import SwiftUI

extension View {
  func touchScrollIndicators(_ visibility: ScrollIndicatorVisibility) -> some View {
    #if targetEnvironment(macCatalyst)
      scrollIndicators(.automatic)
    #else
      scrollIndicators(visibility)
    #endif
  }
}
