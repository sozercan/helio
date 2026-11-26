import SwiftUI

struct CopiableValue: View {
  var value: String
  @State var copied = false
  var body: some View {
    HStack {
      Text("Tap to copy")
        .multilineTextAlignment(.leading)
      Spacer()
      Text(value)
        .multilineTextAlignment(.trailing)
    }
    .padding(.vertical, 12)
    .padding(.horizontal, 16)
    .opacity(0.75)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
    .overlay(
      !copied
        ? nil
        : Text("Copied!")
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RR(16, Color.black.opacity(0.5))),
    )
    .fontSize(15)
    .onTapGesture {
      UIPasteboard.general.string = value
      withAnimation {
        copied = true
      }
      doThisAfter(1.0) {
        withAnimation {
          copied = false
        }
      }
    }
  }
}
