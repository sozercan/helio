//
//  CredentialEditStack.swift
//  Helio
//
//  Created by Igor Marcossi on 01/01/24.
//

import SwiftUI

struct CredentialEditStack: View {
  var credential: RedditCredential
  @State private var player = AVLooperPlayer(url: Bundle.main.url(forResource: "auth-ext", withExtension: "mov")!)
  @State private var draftCredential = RedditCredential()
  @State private var navPath: [Mode] = []

  enum Mode: Int, Hashable { case assistant, advanced, webLogin }

  var body: some View {
    NavigationStack(path: $navPath) {
      CredentialEditView(credential: credential, draftCredential: $draftCredential, navPath: $navPath)
        .navigationDestination(for: Mode.self) { mode in
          switch mode {
          case .assistant: CredentialEditAssistantMode(player: player, draftCredential: $draftCredential, nav: $navPath)
          case .advanced: CredentialEditAdvancedMode(credential: credential, draftCredential: $draftCredential)
          case .webLogin: RedditWebLoginView(credential: draftCredential)
          }
        }
    }
    .onAppear {
      draftCredential = credential
    }
  }
}
