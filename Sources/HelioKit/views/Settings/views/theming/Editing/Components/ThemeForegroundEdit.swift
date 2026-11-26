import SwiftUI

struct ThemeForegroundEdit: View {
  @Binding var theme: ThemeForegroundBG
  var defaultVal: ThemeForegroundBG
  var body: some View {
    Toggle("Blur background", isOn: $theme.blurry)
      .padding(.horizontal, 16)
      .resetter($theme.blurry, defaultVal.blurry)

    Divider()

    LabeledMultiline("Background color") {
      SchemesColorPicker(theme: $theme.color, defaultVal: defaultVal.color)
    }
  }
}
