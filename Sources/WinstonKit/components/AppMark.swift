//
//  AppMark.swift
//  winston
//

import SwiftUI

/// Helio's mark, a sun, for places that show the app itself (welcome, About, credentials).
struct AppMark: View {
  var size: CGFloat

  var body: some View {
    Image(systemName: "sun.max.fill")
      .resizable()
      .scaledToFit()
      .frame(width: size, height: size)
      .foregroundStyle(.yellow.gradient)
      .accessibilityLabel("Helio")
  }
}
