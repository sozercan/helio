//
//  CredentialsPanelEmptyView.swift
//  Helio
//
//  Created by Igor Marcossi on 31/12/23.
//

import Defaults
import SwiftUI

struct CredentialsPanelEmptyView: View {
  var body: some View {
    VStack(spacing: 20) {
      VStack(spacing: 16) {
        Image(systemName: "person.crop.circle.badge.questionmark")
          .fontSize(96)
          .foregroundStyle(.secondary)
        VStack(spacing: 4) {
          Text("Omg, no credentials!")
            .fontSize(24, .bold)
          Text("Sign in to start using Helio.").fontSize(16, .medium).opacity(0.75)
        }
      }

      VStack(spacing: 16) {
        Button("Sign in with Reddit", systemImage: "person.fill.badge.plus") {
          Nav.present(.redditSignIn)
        }
        .buttonStyle(.action)

        Button("Use your own API key", systemImage: "key.fill") {
          Nav.present(.editingCredential(.init()))
        }
        .buttonStyle(.actionOutlined)

        Button(action: {
          Defaults[.GeneralDefSettings].onboardingState = .active
          Nav.present(.onboarding)
        }, label: {
          Label {
            Text("Restart welcome tutorial")
          } icon: {
            Image(systemName: "sun.max.fill")
          }
        })
        .buttonStyle(.actionOutlined)
        .opacity(0.5)
      }
    }
    .compositingGroup()
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
