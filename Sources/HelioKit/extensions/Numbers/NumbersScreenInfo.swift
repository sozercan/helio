import Foundation
import UIKit

extension Double {
  static var screenW: Double {
    WindowMetrics.shared.size.width
  }

  static var screenH: Double {
    WindowMetrics.shared.size.height
  }
}

extension CGFloat {
  static var screenW: CGFloat {
    WindowMetrics.shared.size.width
  }

  static var screenH: CGFloat {
    WindowMetrics.shared.size.height
  }

  static var screenScale: CGFloat {
    WindowMetrics.shared.displayScale
  }
}
