//
//  Tag.swift
//  Helio
//
//  Created by Igor Marcossi on 24/09/23.
//

import Defaults
import SwiftUI

struct Tag: View {
  static let height: Double = 15.6

  var subredditIconKit: SubredditIconKit?
  var text: String
  var fontSize: Double?
  var backgroundColor: Color = .accentColor
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    HStack(spacing: 4) {
      if let subredditIconKit {
        SubredditIcon(subredditIconKit: subredditIconKit, size: 16)
      }
      Text(text)
        .padding(.vertical, 1)
    }
    .contentFont(fontSize ?? 13, .semibold, relativeTo: .meta)
    .padding(.leading, subredditIconKit == nil ? 9 : 0)
    .padding(.trailing, (fontSize ?? 13) * 0.7)
    .background(Capsule(style: .continuous).fill(backgroundColor.opacity(0.2)))
    .foregroundStyle(Color.secondaryText)
    // The default height fits the default text size; it grows with the text.
    .frame(height: fontSize == nil ? ContentTextScale.size(Tag.height, relativeTo: .meta, dynamicTypeSize: dynamicTypeSize) : nil, alignment: .leading)
    .fixedSize(horizontal: true, vertical: false)
    .lineLimit(1)
  }
}
