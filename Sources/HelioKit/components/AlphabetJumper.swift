import SwiftUI

struct AlphabetJumper: View {
  var letters: [String]
  var proxy: ScrollViewProxy
  @GestureState private var scrollLetter = ""
  @State private var haptic = UIImpactFeedbackGenerator(style: .rigid)
  @State private var accessibilityIndex = 0

  func scrollTo(_ letter: String) {
    if !letter.isEmpty {
      proxy.scrollTo(letter, anchor: .center)
      haptic.prepare()
      haptic.impactOccurred()
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      ForEach(letters, id: \.self) { letter in
        Text(letter.uppercased())
          .allowsHitTesting(false)
          .offset(x: scrollLetter == letter ? -48 : 0)
          .padding(.vertical, 1)
          .padding(.trailing, 2)
      }
    }
    .animation(spring, value: scrollLetter.isEmpty)
    .fontSize(11, .semibold)
    .frame(width: 16, alignment: .trailing)
    .background(Color.clear)
    .contentShape(Rectangle())
    .highPriorityGesture(
      DragGesture(minimumDistance: 0)
        .updating($scrollLetter) { val, state, trans in
          let stepI = Int(val.location.y / 15.3)
          if stepI >= letters.count || stepI < 0 {
            return
          }
          if letters.count - 1 >= stepI {
            let newLetter = letters[stepI]
            if newLetter != state {
              trans.animation = spring
              state = newLetter
            }
          }
        },
    )
    .onChange(of: scrollLetter, perform: scrollTo)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Section index")
    .accessibilityValue(letters.indices.contains(accessibilityIndex) ? letters[accessibilityIndex] : "")
    .accessibilityAdjustableAction { direction in
      guard !letters.isEmpty else { return }
      switch direction {
      case .increment: accessibilityIndex = min(max(accessibilityIndex + 1, 0), letters.count - 1)
      case .decrement: accessibilityIndex = min(max(accessibilityIndex - 1, 0), letters.count - 1)
      @unknown default: return
      }
      scrollTo(letters[accessibilityIndex])
    }
    .accessibilityHidden(letters.isEmpty)
    .frame(maxHeight: .infinity, alignment: .trailing)
    .ignoresSafeArea()
    .foregroundStyle(Color.accentColor)
  }
}
