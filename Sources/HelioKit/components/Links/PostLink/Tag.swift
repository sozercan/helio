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

  var body: some View {
    HStack(spacing: 4) {
      if let subredditIconKit {
        SubredditIcon(subredditIconKit: subredditIconKit, size: 16)
      }
      Text(text)
        .padding(.vertical, 1)
    }
    .fontSize(fontSize ?? 13, .semibold)
    .padding(.leading, subredditIconKit == nil ? 9 : 0)
    .padding(.trailing, (fontSize ?? 13) * 0.7)
    .background(Capsule(style: .continuous).fill(backgroundColor.opacity(0.2)))
    .foregroundColor(.primary.opacity(0.5))
    .frame(height: fontSize == nil ? Tag.height : nil, alignment: .leading)
    .fixedSize(horizontal: true, vertical: false)
    .lineLimit(1)
  }
}
