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
  /// Scores in the vote colors: the button fills are too light for text on white (3.1:1) and
  /// too dark on black, so text uses shades that reach 4.5:1.
  static let upvoteText = Color(UIColor(light: UIColor(hex: "C84300"), dark: UIColor(hex: "F36700")))
  static let downvoteText = Color(UIColor(light: UIColor(hex: "565FE3"), dark: UIColor(hex: "7B7CE8")))
}

/// An arrow that fills a rounded square with its vote color while active.
struct VoteButton: View, Equatable {
  static let size: CGFloat = 30
  /// The tap target around the drawn square, so adjacent buttons stay easy to hit.
  static let hitSize: CGFloat = 44

  static func == (lhs: VoteButton, rhs: VoteButton) -> Bool {
    lhs.active == rhs.active && lhs.color == rhs.color && lhs.image == rhs.image && lhs.label == rhs.label
  }

  var active: Bool
  var color: Color
  var image: String
  /// What VoiceOver calls it, "Upvote" or "Downvote".
  var label: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: image)
        .font(.system(size: 17, weight: .medium))
        .symbolEffect(active ? .bounce.up : .bounce.down, options: .speed(2.75), value: active)
        .foregroundStyle(active ? Color.white : Color.secondary)
        .frame(width: VoteButton.size, height: VoteButton.size)
        .background(color.opacity(active ? 1 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(width: VoteButton.hitSize, height: VoteButton.hitSize)
        .contentShape(Rectangle())
        .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 10, style: .continuous).inset(by: 5))
    }
    .buttonStyle(.plain)
    .hoverEffect(.highlight)
    .accessibilityLabel(label)
    .accessibilityAddTraits(active ? .isSelected : [])
  }
}
