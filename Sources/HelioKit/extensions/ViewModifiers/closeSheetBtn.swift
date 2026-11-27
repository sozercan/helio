import SwiftUI

extension View {
  func closeSheetBtn(_ action: @escaping () -> Void) -> some View {
    self
      .overlay(
        Button(action: action) {
          Image(systemName: "xmark.circle.fill")
            .fontSize(24)
            .opacity(0.5)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.all, 6),
        alignment: .topTrailing,
      )
  }
}
