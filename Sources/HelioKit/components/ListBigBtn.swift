import Defaults
import SwiftUI

struct ListBigBtn: View {
  var icon: String
  var iconColor: Color
  var label: String
  var shiny: Gradient?
  var selected = false
  var action: () -> Void

  @State private var pressed = false

  var body: some View {
    let isNotCircled = !icon.contains("circle")
    Button(action: action) {
      VStack(alignment: .leading, spacing: 8) {
        Image(systemName: icon)
          .symbolRenderingMode(.palette)
          .foregroundStyle(.white, iconColor)
          .fontSize(isNotCircled ? 20 : 32)
          .padding(isNotCircled ? 5 : 0)
        Text(label)
          .fontSize(17, .semibold)
      }
      .padding(.all, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .foregroundColor(.primary)
      .themedListRowLikeBG(pressed: pressed, shiny: shiny)
      .mask(RoundedRectangle(cornerRadius: 10).foregroundColor(.black))
      .overlay {
        if selected {
          RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 2)
        }
      }
      .contentShape(RoundedRectangle(cornerRadius: 13))
    }
    .buttonStyle(ButtonPressingProviderStyle(pressed: $pressed))
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
