//
//  EndOfFeedView.swift
//  Helio
//
//  Created by Ethan Bills on 11/21/23.
//

import SwiftUI

struct EndOfFeedView: View {
  @State private var tapCount = 0
  @State private var showAlert = false

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: "sun.horizon.fill")
        .font(.system(size: 36))
        .foregroundStyle(.orange.gradient)
      Text(QuirkyMessageUtil.quirkyEndOfFeed())
        .fixedSize(horizontal: false, vertical: true)
        .font(.system(size: 16, weight: .bold))
        .multilineTextAlignment(.center)
        .lineLimit(4)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.quaternary)
    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 150, maxHeight: 150, alignment: .center)
//    .fixedSize()
    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    .onTapGesture {
      self.handleTap()
    }
    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
//    .padding(.horizontal, 24)
    .alert(isPresented: $showAlert) {
      Alert(
        title: Text("Secrets Unveiled"),
        message: Text(QuirkyMessageUtil.quirkyGoAwayMessage()),
        dismissButton: .default(Text("OK")),
      )
    }
  }

  private func handleTap() {
    tapCount += 1

    if tapCount >= 5 {
      showAlert = true
      tapCount = 0
    }
  }
}
