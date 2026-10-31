//
//  OnboardingAPIIntro.swift
//  Helio
//
//  Created by Igor Marcossi on 01/08/23.
//

import SwiftUI

private struct Feature: View {
  var icon: String
  var title: String
  var description: String
  @Environment(\.colorScheme) var colorScheme: ColorScheme
  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .foregroundColor(.blue)
        .fontSize(32, .semibold)
        .frame(width: 40)
      VStack(alignment: .leading, spacing: 0) {
        Text(.init(title))
          .fontSize(17, .semibold)

        Text(.init(description))
          .fontSize(15)
          .opacity(0.75)
      }
    }
    .padding(.leading, 12)
    .padding(.vertical, 12)
    .padding(.trailing, 16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RR(16, Color.black.opacity(colorScheme == .dark ? 0.2 : 0.05)))
  }
}

struct OnboardingAPIIntro: View {
  var prevStep: () -> Void
  var nextStep: () -> Void
  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        VStack {
          Text("First, sign in to Reddit")
            .fontSize(24, .semibold)
          Text("You sign in on Reddit's own website, right inside Helio.")
            .opacity(0.75)
        }
        .multilineTextAlignment(.center)

        VStack(spacing: 6) {
          Feature(icon: "person.crop.circle.badge.checkmark", title: "No API key needed", description: "Just your Reddit account, nothing to set up.")
          Feature(icon: "eye.slash.fill", title: "Safe and private", description: "Your sign-in is **only** stored in your keychain and only ever sent to Reddit.")
          Feature(icon: "key.fill", title: "Prefer your own key?", description: "You can still use an API key you made on Reddit's site.")
        }

        VStack(spacing: 12) {
          MasterButton(label: "Sign in with Reddit", colorHoverEffect: .animated, textSize: 18, height: 48, fullWidth: true, cornerRadius: 16, action: {
            Nav.present(.redditSignIn)
          })

          Button("Use my own API key") {
            Nav.present(.editingCredential(.init()))
          }
          .fontSize(16, .medium)
        }
        .padding(.top, 32)
      }
      .padding(.top, 64)
      .padding(.horizontal, 16)
    }
  }
}
