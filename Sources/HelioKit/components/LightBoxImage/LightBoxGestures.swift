import UIKit

enum LightBoxScrub {
  case began
  case moved(CGFloat)
  case ended
}

@MainActor
final class LightBoxGestures: NSObject, UIGestureRecognizerDelegate {
  static let holdDuration: TimeInterval = 0.3

  var onHold: ((LightBoxScrub) -> Void)?
  var onSwipe: ((Int) -> Void)?
  var isZoomed: () -> Bool = { false }

  private(set) var hold: UILongPressGestureRecognizer?
  private var holdStart: CGPoint?

  func install(on view: UIView) {
    let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleHold(_:)))
    hold.minimumPressDuration = Self.holdDuration
    hold.allowableMovement = 10
    hold.delegate = self
    view.addGestureRecognizer(hold)
    self.hold = hold

    let swipe = UIPanGestureRecognizer(target: self, action: #selector(handleTrackpadSwipe(_:)))
    swipe.allowedScrollTypesMask = .continuous
    swipe.allowedTouchTypes = []
    swipe.delegate = self
    view.addGestureRecognizer(swipe)
  }

  @objc private func handleHold(_ gestureRecognizer: UILongPressGestureRecognizer) {
    let location = gestureRecognizer.location(in: gestureRecognizer.view)
    switch gestureRecognizer.state {
    case .began:
      guard let onHold, !isZoomed() else { return }
      holdStart = location
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      onHold(.began)
    case .changed:
      if let holdStart {
        onHold?(.moved(location.x - holdStart.x))
      }
    case .ended, .cancelled, .failed:
      if holdStart != nil {
        holdStart = nil
        onHold?(.ended)
      }
    default:
      break
    }
  }

  @objc private func handleTrackpadSwipe(_ gestureRecognizer: UIPanGestureRecognizer) {
    guard gestureRecognizer.state == .ended, let onSwipe, !isZoomed() else { return }
    let translation = gestureRecognizer.translation(in: gestureRecognizer.view)
    let velocity = gestureRecognizer.velocity(in: gestureRecognizer.view)
    guard abs(translation.x) > abs(translation.y), abs(translation.x) > 60 || abs(velocity.x) > 400 else { return }
    onSwipe(translation.x < 0 ? 1 : -1)
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
    true
  }
}
