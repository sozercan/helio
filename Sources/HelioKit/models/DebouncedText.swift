//
//  DebouncedText.swift
//  Helio
//
//  Created by Igor Marcossi on 27/07/23.
//

import Foundation

@Observable
class Debouncer<V> {
  private var timer = TimerHolder()
  private var delay: Double
  @ObservationIgnored private var settingNow = false
  var value: V {
    didSet {
      guard !settingNow else { return }
      timer.fireIn(delay) {
        self.debounced = self.value
      }
    }
  }

  private(set) var debounced: V

  /// Sets `value` and `debounced` at once, without waiting.
  func setNow(_ newValue: V) {
    settingNow = true
    value = newValue
    settingNow = false
    debounced = newValue
  }

  init(_ val: V, delay: Double = 0.4) {
    value = val
    debounced = val
    self.delay = delay
  }
}
