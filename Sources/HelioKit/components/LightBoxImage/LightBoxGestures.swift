//
//  LightBoxGestures.swift
//  Helio
//

import UIKit

/// A held drag on a GIF or video: the hold, the finger's sideways travel since, and its lift.
enum LightBoxScrub {
  case began
  case moved(CGFloat)
  case ended
}

/// The lightbox page's UIKit gestures, added to the view that shows the media.
///
/// - Holding a finger still on a GIF or video, then dragging, scrubs it. The hold follows the finger
///   itself, as the lightbox's drag may be cancelled once the hold begins.
/// - A two-finger swipe on a trackpad (Mac, or an iPad's) pages, which the lightbox's drag never
///   sees. It takes scroll events only, so touches still go to that drag.
@MainActor
final class LightBoxGestures: NSObject, UIGestureRecognizerDelegate {
  /// How long a finger rests before a drag scrubs.
  static let holdDuration: TimeInterval = 0.3

  /// A held drag's events.
  var onHold: ((LightBoxScrub) -> Void)?
  /// A trackpad swipe sideways, by -1 (back) or 1 (on).
  var onSwipe: ((Int) -> Void)?
  /// A zoomed image pans instead of paging.
  var isZoomed: () -> Bool = { false }

  private(set) var hold: UILongPressGestureRecognizer?
  /// Where the finger was when the hold began.
  private var holdStart: CGPoint?

  func install(on view: UIView) {
    let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleHold(_:)))
    hold.minimumPressDuration = Self.holdDuration
    // A finger that moves first is a swipe.
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

  /// Pages once the fingers lift from a mostly sideways swipe.
  @objc private func handleTrackpadSwipe(_ gestureRecognizer: UIPanGestureRecognizer) {
    guard gestureRecognizer.state == .ended, let onSwipe, !isZoomed() else { return }
    let translation = gestureRecognizer.translation(in: gestureRecognizer.view)
    let velocity = gestureRecognizer.velocity(in: gestureRecognizer.view)
    guard abs(translation.x) > abs(translation.y), abs(translation.x) > 60 || abs(velocity.x) > 400 else { return }
    // Fingers moving left bring in the next page, as a touch swipe does.
    onSwipe(translation.x < 0 ? 1 : -1)
  }

  /// The lightbox's drag and the zoom view's gestures go on alongside.
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
    true
  }
}
