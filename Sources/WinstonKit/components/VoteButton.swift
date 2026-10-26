//
//  VoteButton.swift
//  winston
//
//  Created by Daniel Inama on 12/08/23.
//

import SwiftUI

struct VoteButton: View, Equatable {
  var active: Bool
  var color: Color
  var image: String
  
  var body: some View {
    Image(systemName: image)
      .symbolEffect(active ? .bounce.up : .bounce.down, options: .speed(2.75), value: active)
      .frame(21)
      .increaseHitboxBy(8)
      .foregroundColor(active ? color : .gray)
  }
}
