import SwiftUI

struct DataBlock: View {
  var icon: String
  var label: String
  var value: String
  var iconColor: Color?
  var labelColor: Color?
  var valueColor: Color?
  @Environment(\.useTheme) private var theme

  var body: some View {
    VStack(spacing: 4) {
      Image(systemName: icon)
        .fontSize(20, .semibold)
        .foregroundStyle(iconColor ?? theme.general.accentColor())
      VStack(spacing: 0) {
        Text(label)
          .fontSize(14)
          .foregroundStyle(labelColor ?? theme.postLinks.theme.badge.statsText.color())
        Text(value)
          .fontSize(18, .semibold)
          .foregroundStyle(valueColor ?? theme.postLinks.theme.titleText.color())
      }
    }
    .padding(.all, 8)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .themedListRowLikeBG()
    .mask(RR(20, Color.black))
  }
}
