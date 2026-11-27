import SwiftUI

struct VDivider: View {
  @Environment(\.useTheme) private var currentTheme
  var body: some View {
    Rectangle()
      .fill(currentTheme.lists.dividersColors())
      .frame(maxWidth: 0.5, maxHeight: .infinity)
  }
}
