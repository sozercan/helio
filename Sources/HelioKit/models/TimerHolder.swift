//
//  TimerHolder.swift
//  Helio
//
//  Created by Igor Marcossi on 06/01/24.
//

import SwiftUI

class TimerHolder {
  var timer: Timer?

  init() {}

  func fireIn(_ secs: Double, _ cb: @escaping () -> Void) {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: secs, repeats: false) { _ in
      cb()
    }
  }

  func every(_ secs: Double, _ cb: @escaping () -> Void) {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: secs, repeats: true) { _ in
      cb()
    }
  }

  func invalidate() {
    timer?.invalidate()
  }
}
