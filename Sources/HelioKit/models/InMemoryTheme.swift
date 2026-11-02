//
//  InMemoryTheme.swift
//  Helio
//
//  Created by Igor Marcossi on 25/01/24.
//

import Defaults
import Foundation
import SwiftUI

@Observable
class InMemoryTheme {
  static let shared = InMemoryTheme()
  var currentTheme: HelioTheme = defaultTheme
  var currTask: Task<Void, Never>?

  init() {
    self.currentTheme = HelioTheme.selected(in: Defaults[.ThemesDefSettings])
    self.currTask = Task {
      for await value in Defaults.updates(.ThemesDefSettings) {
        self.currentTheme = HelioTheme.selected(in: value)
      }
    }
  }

  deinit {
    currTask?.cancel()
  }
}
