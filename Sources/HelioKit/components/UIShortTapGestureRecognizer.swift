import Foundation
import UIKit

class UIShortTapGestureRecognizer: UITapGestureRecognizer {
  var maximumTapLength: Double = 0.35

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesBegan(touches, with: event)
    delay(delay: maximumTapLength) {
      if self.state != .ended {
        self.state = .failed
      }
    }
  }

  func delay(delay: Double, closure: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: closure)
  }
}
