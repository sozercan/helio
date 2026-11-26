import SwiftUI

struct EndOfFeedView: View {
  @State private var tapCount = 0
  @State private var showAlert = false

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: "sun.horizon.fill")
        .font(.system(size: 36))
        .foregroundStyle(.orange.gradient)
      Text(QuirkyMessageUtil.quirkyEndOfFeed())
        .fixedSize(horizontal: false, vertical: true)
        .contentFont(16, .bold)
        .multilineTextAlignment(.center)
        .lineLimit(4)
    }
    .padding()
    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 150, alignment: .center)
    .contentShape(Rectangle())
    .onTapGesture {
      self.handleTap()
    }
    .listRowInsets(EdgeInsets())
    .alert(isPresented: $showAlert) {
      Alert(
        title: Text("Secrets Unveiled"),
        message: Text(QuirkyMessageUtil.quirkyGoAwayMessage()),
        dismissButton: .default(Text("OK")),
      )
    }
  }

  private func handleTap() {
    tapCount += 1

    if tapCount >= 5 {
      showAlert = true
      tapCount = 0
    }
  }
}
