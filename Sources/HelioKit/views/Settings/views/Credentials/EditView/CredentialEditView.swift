//
//  CredentialEditView.swift
//  Helio
//
//  Created by Igor Marcossi on 22/11/23.
//

import NukeUI
import SwiftUI

struct CredentialEditView: View {
  var credential: RedditCredential
  @Binding var draftCredential: RedditCredential
  @Binding var navPath: [CredentialEditStack.Mode]

  @Environment(\.useTheme) private var theme
  @Environment(\.colorScheme) private var cs
  @Environment(\.dismiss) private var dismiss

  var creating: Bool {
    !draftCredential.isInKeychain()
  }

  func showBtns() -> some View {
    VStack(spacing: creating ? 16 : 14) {
      BigCredBtn(nav: $navPath, img: { AppMark(size: 52) }, title: draftCredential.isWebSession ? "Sign in again" : "Sign in with Reddit", description: "Sign in on Reddit's website. No API key needed.", page: .webLogin, recommended: true)

      Text("Or use your own API key")
        .fontSize(15, .semibold)
        .opacity(0.6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)

      BigCredBtn(nav: $navPath, img: { Image(systemName: "key.fill").fontSize(40, .semibold).foregroundStyle(Color.accentColor) }, title: !creating ? "Guided replace" : "Guided mode", description: "A guided walkthrough to \(!creating ? "replace this credential by another" : "generate or select a credential").", page: .assistant)
      BigCredBtn(nav: $navPath, img: { Image(systemName: "gear").fontSize(44, .semibold).foregroundStyle(Color.accentColor) }, title: !creating ? "Advanced settings" : "Advanced mode", description: "Manually \(creating ? "enter" : "edit") your credentials and get nerd info.", page: .advanced)
    }
    .frame(maxWidth: .infinity)
  }

  var body: some View {
    let anyChanges = credential != draftCredential
    let accentColor = theme.general.accentColor.cs(cs).color()

    Group {
      if creating {
        VStack(spacing: 32) {
          VStack(spacing: 16) {
            BetterLottieView("keys", size: 120, color: accentColor)

            VStack(spacing: 4) {
              Text("Create Credential").fontSize(32, .bold)
              Text("Sign in with your Reddit account, or bring your own API key.")
            }
          }

          showBtns()
        }
        .padding(.top, 48)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            EditCredentialProfile(pictureURL: draftCredential.profilePicture, username: draftCredential.userName ?? "New credential", statusInfo: draftCredential.validationStatus.getMeta())

            EditCredWhatToDoBanner(draftCredential: $draftCredential)

            VStack(alignment: .leading, spacing: 10) {
              Text("What else can you do").fontSize(21, .semibold)
              showBtns()
            }
          }
          .animation(.spring, value: draftCredential.validationStatus)
          .padding(.all, 16)
        }
      }
    }
    .themedListBG(theme.lists.bg)
    .toolbar {
      ToolbarItem(placement: .topBarLeading) { Button("Cancel", role: .destructive) { dismiss() } }
      ToolbarItem(placement: .topBarTrailing) { Button("Save") { draftCredential.save()
        dismiss()
      }.disabled(!anyChanges) }
    }
    .multilineTextAlignment(.center)
    .navigationTitle(creating ? "New credential" : "Edit credential")
    .navigationBarTitleDisplayMode(.inline)
  }
}
