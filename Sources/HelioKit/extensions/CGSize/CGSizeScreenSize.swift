import Foundation

extension CGSize {
  static var screenSize: CGSize {
    WindowMetrics.shared.size
  }
}
