//
//  SubsNStuffLine.swift
//  Helio
//
//  Created by Igor Marcossi on 24/09/23.
//

import SwiftUI

struct SubsNStuffLine: View, Equatable {
  static func == (lhs: SubsNStuffLine, rhs: SubsNStuffLine) -> Bool {
    true
  }

  ///  static let height = Tag.height + 4
  static let height: CGFloat = 1

  var body: some View {
    HStack(spacing: 0) {
      WDivider()
    }
    .padding(.horizontal, 2)
    .frame(height: SubsNStuffLine.height)
    //    }
  }
}
