import SwiftUI

struct ButtonPressingProviderStyle: ButtonStyle {
  @Binding var pressed: Bool
  var isButton = false
  func makeBody(configuration: Self.Configuration) -> some View {
    configuration.label
      .foregroundStyle(isButton ? Color.accentColor : .primary)
      .onChange(of: configuration.isPressed) { pressed = $0 }
  }
}
