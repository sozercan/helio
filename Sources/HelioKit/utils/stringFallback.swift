//
//  stringFallback.swift
//  Helio
//
//  Created by Igor Marcossi on 31/07/23.
//

import Foundation

extension String {
  func fallback(_ str: String) -> String {
    self.isEmpty ? str : self
  }
}
