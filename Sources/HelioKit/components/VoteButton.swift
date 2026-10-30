//
//  VoteButton.swift
//  Helio
//
//  Created by Daniel Inama on 12/08/23.
//

import SwiftUI

extension Color {
  static let upvote = Color(UIColor(light: UIColor(hex: "FF5D00"), dark: UIColor(hex: "F36700")))
  static let downvote = Color(UIColor(light: UIColor(hex: "565FE3"), dark: UIColor(hex: "6263E1")))
}

/// An arrow that fills a rounded square with its vote color while active.
struct VoteButton: View, Equatable {
  static let size: CGFloat = 30

  var active: Bool
  var color: Color
  var image: String

  var body: some View {
    Image(systemName: image)
      .font(.system(size: 17, weight: .medium))
      .symbolEffect(active ? .bounce.up : .bounce.down, options: .speed(2.75), value: active)
      .foregroundStyle(active ? Color.white : Color.secondary)
      .frame(width: VoteButton.size, height: VoteButton.size)
      .background(color.opacity(active ? 1 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      .contentShape(Rectangle())
      .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
  }
}
