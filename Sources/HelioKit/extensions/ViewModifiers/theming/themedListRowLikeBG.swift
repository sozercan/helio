import Foundation
import SwiftUI

struct ThemedListRowLikeBGModifier: ViewModifier {
  var enablePadding = false
  var disableBG = false
  var active = false
  var pressed = false
  var shiny: Gradient?
  var opacity: Double = 1

  @Environment(\.useTheme) private var theme

  func body(content: Content) -> some View {
    let isActive = active && isWideLayout
    return content
      .padding(.horizontal, enablePadding ? 16 : 0)
      .padding(.vertical, enablePadding ? 8 : 0)
      .frame(maxWidth: .infinity, minHeight: 45, alignment: .leading)
      .background(disableBG ? nil : ThemedForegroundBG(theme: theme.lists.foreground, active: isActive, pressed: pressed, shiny: shiny).opacity(opacity))
  }
}

extension View {
  func themedListRowLikeBG(enablePadding: Bool = false, disableBG: Bool = false, active: Bool = false, pressed: Bool = false, shiny: Gradient? = nil, opacity: Double = 1) -> some View {
    self.modifier(ThemedListRowLikeBGModifier(enablePadding: enablePadding, disableBG: disableBG, active: active, pressed: pressed, shiny: shiny, opacity: opacity))
  }
}

private struct HairlineRowSeparator: ViewModifier {
  var leading: CGFloat
  @Environment(\.useTheme) private var theme

  func body(content: Content) -> some View {
    content.overlay(alignment: .bottom) {
      theme.lists.dividersColors()
        .frame(height: 0.5)
        .padding(.leading, leading)
        .allowsHitTesting(false)
    }
  }
}

extension View {
  func hairlineRowSeparator(leading: CGFloat = 16) -> some View {
    modifier(HairlineRowSeparator(leading: leading))
  }
}
