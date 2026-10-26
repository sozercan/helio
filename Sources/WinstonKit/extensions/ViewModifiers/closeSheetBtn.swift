//
//  closeSheetBtn.swift
//  winston
//
//  Created by Igor Marcossi on 31/08/23.
//

import SwiftUI

extension View {
  func closeSheetBtn(_ action: @escaping ()->()) -> some View {
    self
      .overlay(
        Button(action: action) {
          Image(systemName: "xmark.circle.fill")
            .fontSize(24)
            .opacity(0.5)
            // A 44pt target, extending below the top edge of iPad form sheets, where taps
            // on the bare 24pt icon never reached the button.
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
          .buttonStyle(.plain)
          .padding(.all, 6)
        , alignment: .topTrailing
      )
  }
}
