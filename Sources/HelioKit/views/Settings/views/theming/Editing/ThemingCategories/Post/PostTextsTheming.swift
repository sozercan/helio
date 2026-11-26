import SwiftUI

struct PostTextsTheming: View {
  @Binding var theme: PostTheme
  var body: some View {
    FakeSection("Title") {
      FontSelector(theme: $theme.titleText, defaultVal: defaultTheme.posts.titleText)
    }

    FakeSection("Body") {
      FontSelector(theme: $theme.bodyText, defaultVal: defaultTheme.posts.bodyText)
    }

    FakeSection("Line Spacing") {
      LabeledSlider(label: "Line spacing", value: $theme.linespacing, range: 0 ... 64)
        .resetter($theme.linespacing, defaultTheme.posts.linespacing)
    }
  }
}
