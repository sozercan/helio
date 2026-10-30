//
//  Shiny.swift
//  Helio
//
//  Created by daniel on 23/11/23.
//

import SwiftUI

/// Tints content with the first color of a gradient, or the theme's body text color.
struct ShinyModifier: ViewModifier {
  var shiny: Gradient?
  @Environment(\.useTheme) private var theme

  func body(content: Content) -> some View {
    content.foregroundColor(shiny?.stops.first?.color ?? theme.posts.bodyText.color())
  }
}

extension View {
  func helioShiny(_ shiny: Gradient? = nil) -> some View {
    self.modifier(ShinyModifier(shiny: shiny))
  }
}
