//
//  if.swift
//  Helio
//
//  Created by Igor Marcossi on 28/06/23.
//

import SwiftUI

extension View {
  @ViewBuilder func `if`(_ condition: Bool, transform: (Self) -> some View) -> some View {
    if condition {
      transform(self)
    } else {
      self
    }
  }

  @ViewBuilder func ifLet<E: Any>(_ el: E?, transform: (Self, E) -> some View) -> some View {
    if let el {
      transform(self, el)
    } else {
      self
    }
  }
}
