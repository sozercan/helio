import SwiftUI

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
