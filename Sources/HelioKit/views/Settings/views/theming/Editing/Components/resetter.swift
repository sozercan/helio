import SwiftUI

struct ResetterModifier<T>: ViewModifier {
  @Binding var thing: T
  var defaultVal: T
  @State var opened = false

  func body(content: Content) -> some View {
    content
      .contentShape(Rectangle())
      .onTapGesture {}
      .gesture(
        LongPressGesture(maximumDistance: 0)
          .onEnded { _ in
            opened = true
          },
      )
      .sensoryFeedback(.impact(weight: .medium), trigger: opened) { _, newValue in newValue }
      .alert("Do you wanna reset this property?", isPresented: $opened) {
        VStack {
          Button("Yes, reset", role: .destructive) {
            thing = defaultVal
          }
          Button("Cancel", role: .cancel) {}
        }
      }
  }
}

extension View {
  func resetter<T>(_ thing: Binding<T>, _ defaultVal: T) -> some View {
    self.modifier(ResetterModifier(thing: thing, defaultVal: defaultVal))
  }
}
