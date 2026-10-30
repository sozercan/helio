//
//  themedListSection.swift
//  Helio
//
//  Created by Igor Marcossi on 06/12/23.
//

import Foundation
import SwiftUI

/// A view modifier to apply a themed background to a list row.
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
