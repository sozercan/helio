import SwiftUI

struct SchemesBGImagesPicker: View {
  @Binding var theme: ColorSchemes<String>
  var defaultVal: ColorSchemes<String>

  var body: some View {
    HStack {
      ImageThemePicker(label: "Light", image: $theme.light)
        .resetter($theme.light, defaultVal.light)

      VDivider()

      ImageThemePicker(label: "Dark", image: $theme.dark)
        .resetter($theme.dark, defaultVal.dark)
    }
    .padding(.horizontal, 16)
  }
}
