import SwiftUI

struct AppMark: View {
  var size: CGFloat

  var body: some View {
    Image(systemName: "sun.max.fill")
      .resizable()
      .scaledToFit()
      .frame(width: size, height: size)
      .foregroundStyle(.yellow.gradient)
      .accessibilityLabel("Helio")
  }
}
