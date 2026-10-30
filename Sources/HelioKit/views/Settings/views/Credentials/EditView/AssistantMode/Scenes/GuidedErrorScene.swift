//
//  GuidedErrorScene.swift
//  Helio
//
//  Created by Igor Marcossi on 06/01/24.
//

import SwiftUI

struct GuidedErrorScene: View {
  let text: String
  @Binding var nav: [CredentialEditStack.Mode]
  @Binding var scene: CredentialEditAssistantMode.AssistantScene
  @Environment(\.openURL) private var openURL
  var body: some View {
    VStack(spacing: 40) {
      VStack(spacing: 8) {
        BetterLottieView("error-appear", size: 128, color: .red)
        VStack(spacing: 4) {
          Text("OMG!").fontSize(32, .bold)
          Text(text).opacity(0.9)
        }
      }
      VStack(spacing: 16) {
        HelioButton {
          withAnimation(.spring) { scene = .tutorial }
        } label: {
          Label("Repeat tutorial", systemImage: "arrow.clockwise")
        }

        HelioButton(config: .secondary) {
          nav.append(.advanced)
        } label: {
          Text("I wanna do it manually")
        }

        HelioButton(config: .secondary) {
          openURL(URL(string: "https://discord.gg/Jw3Syb3nrz")!)
        } label: {
          HStack {
            Image(.discordLogo).size(20)
            Text("Ask in the Discord server")
          }
        }
      }
    }
    .multilineTextAlignment(.center)
    .padding(EdgeInsets(top: 64, leading: 32, bottom: 0, trailing: 32))
    .frame(maxHeight: .infinity, alignment: .top)
  }
}
