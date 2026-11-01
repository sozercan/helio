//
//  PostLinkTitle.swift
//  Helio
//
//  Created by Igor Marcossi on 25/09/23.
//

import SwiftUI

struct PostLinkTitle: View, Equatable {
  static func == (lhs: PostLinkTitle, rhs: PostLinkTitle) -> Bool {
    lhs.label == rhs.label && lhs.size == rhs.size && lhs.theme == rhs.theme && lhs.dimmed == rhs.dimmed
  }

  var attrString: NSAttributedString?
  var label: String
  var theme: ThemeText
  var size: CGSize
  /// Read posts get a muted title, like Apollo.
  var dimmed = false
  var dimmedColor: ColorSchemes<ThemeColor>?

  var body: some View {
    if let attrString {
      Prepend(attrString: attrString, title: label, fontWeight: theme.weight.ut, color: (dimmed ? dimmedColor ?? theme.color : theme.color).uiColor(), size: size)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }
    //                  Text(label)
    //                    .fontSize(theme.size, theme.weight.t)
    //                    .fixedSize(horizontal: false, vertical: true)
    //                    .frame(maxWidth: .infinity, alignment: .topLeading)
  }
}
