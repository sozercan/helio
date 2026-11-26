import Foundation
import SwiftUI

struct ThemedListSectionModifier: ViewModifier {
  var disable = false
  @Environment(\.useTheme) private var theme

  func body(content: Content) -> some View {
    if disable {
      content
    } else {
      content
        .listRowBackground(ThemedForegroundBG(theme: theme.lists.foreground))
        .listRowSeparatorTint(theme.lists.dividersColors())
    }
  }
}

extension View {
  func themedListSection(disable: Bool = false) -> some View {
    self.modifier(ThemedListSectionModifier(disable: disable))
  }
}
