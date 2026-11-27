import SwiftUI

struct GuidedAuthSuccessScene: View {
  private static let celebrationSequence: [Hap.TransientBeat] = [
    .init(relativeTime: 0.1, intensity: 1, sharpness: 0.85),
    .init(relativeTime: 0.6, intensity: 0.35, sharpness: 1),
    .init(relativeTime: 0.63, intensity: 0.35, sharpness: 1),
    .init(relativeTime: 0.745, intensity: 0.55, sharpness: 1),
    .init(relativeTime: 0.75, intensity: 0.45, sharpness: 1),
    .init(relativeTime: 0.8, intensity: 0.45, sharpness: 1),
    .init(relativeTime: 0.815, intensity: 0.25, sharpness: 1),
    .init(relativeTime: 0.84, intensity: 0.45, sharpness: 1),
    .init(relativeTime: 0.845, intensity: 0.35, sharpness: 1),
    .init(relativeTime: 1.15, intensity: 0.75, sharpness: 1),
    .init(relativeTime: 1.35, intensity: 0.45, sharpness: 1),
    .init(relativeTime: 1.45, intensity: 0.65, sharpness: 1),
    .init(relativeTime: 1.7, intensity: 0.5, sharpness: 1),
  ]

  private static let saveButtonSequence: [Hap.TransientBeat] = [
    .init(relativeTime: 0, intensity: 0.75, sharpness: 0.5),
    .init(relativeTime: 0.1, intensity: 0.9, sharpness: 1),
  ]

  let draftCredential: RedditCredential
  var body: some View {
    VStack(spacing: 40) {
      VStack(spacing: 8) {
        BetterLottieView("party-appear", size: 128, skipInitialProgress: 0.02, color: nil)
        VStack(spacing: 4) {
          Text("Sweeeet!").fontSize(32, .bold)
          Text("Everything went well. You can start using Helio now!").opacity(0.9)
        }
      }
      VStack(spacing: 16) {
        HelioButton {
          Hap.shared.playSequence(Self.saveButtonSequence)
          draftCredential.save()
          Nav.present(nil)
        } label: {
          Label("Save and let's rock!", systemImage: "balloon.fill")
        }
      }
    }
    .multilineTextAlignment(.center)
    .overlay(alignment: .top) {
      BetterLottieView("confetti-magic", size: .screenW, initialDelay: 0.1, color: nil)
        .padding(.top, -176)
        .allowsHitTesting(false)
    }
    .padding(EdgeInsets(top: 64, leading: 32, bottom: 0, trailing: 32))
    .frame(maxHeight: .infinity, alignment: .top)
    .onAppear {
      Hap.shared.playSequence(Self.celebrationSequence)
    }
  }
}
