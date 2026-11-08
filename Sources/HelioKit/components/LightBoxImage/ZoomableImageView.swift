//
//  ZoomableImageView.swift
//  Helio
//
//  Created by Daniel Inama on 27/08/23.
//

import Foundation
import SwiftUI
import UIKit

/// Source https://stackoverflow.com/a/64110231
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
  private var content: Content
  private var onTap: (() -> Void)?
  private var onSwipe: ((Int) -> Void)?
  @Binding var isZoomed: Bool // Add the binding parameter

  init(onTap: (() -> Void)? = nil, onSwipe: ((Int) -> Void)? = nil, isZoomed: Binding<Bool>, @ViewBuilder content: () -> Content) {
    self.content = content()
    // set up helper class
    self.onTap = onTap
    self.onSwipe = onSwipe
    self._isZoomed = isZoomed // Initialize the binding
  }

  func makeUIView(context: Context) -> UIScrollView {
    // set up the UIScrollView
    let scrollView = UIScrollView()
    scrollView.delegate = context.coordinator // for viewForZooming(in:)
    scrollView.maximumZoomScale = 20
    scrollView.minimumZoomScale = 1
    scrollView.bouncesZoom = true
    scrollView.bounces = true
    scrollView.showsVerticalScrollIndicator = false
    scrollView.showsHorizontalScrollIndicator = false

    // create a UIHostingController to hold our SwiftUI content
    let hostedView = context.coordinator.hostingController.view!
    hostedView.translatesAutoresizingMaskIntoConstraints = true
    hostedView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    hostedView.frame = scrollView.bounds
    scrollView.addSubview(hostedView)
    scrollView.contentSize = hostedView.frame.size

    let doubleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
    doubleTapGesture.numberOfTapsRequired = 2
    scrollView.addGestureRecognizer(doubleTapGesture)

    let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
    tapGesture.numberOfTapsRequired = 1
    tapGesture.require(toFail: doubleTapGesture)
    scrollView.addGestureRecognizer(tapGesture)

    // A two-finger swipe on a trackpad (Mac, or an iPad's), which the drag that pages by touch
    // never sees. Scroll events only: touches still go to that drag.
    let swipeGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTrackpadSwipe(_:)))
    swipeGesture.allowedScrollTypesMask = .continuous
    swipeGesture.allowedTouchTypes = []
    swipeGesture.delegate = context.coordinator
    scrollView.addGestureRecognizer(swipeGesture)

    return scrollView
  }

  func updateUIView(_ uiView: UIScrollView, context: Context) {
    // update the hosting controller's SwiftUI content
    context.coordinator.hostingController.rootView = self.content
    context.coordinator.onSwipe = onSwipe
    assert(context.coordinator.hostingController.view.superview == uiView)

    // While not zoomed, keep contentSize matching the view, so the next pinch scales
    // from the right baseline instead of a stale or zero size (black bars, erratic panning).
    if uiView.zoomScale == uiView.minimumZoomScale {
      let hostedView = context.coordinator.hostingController.view!
      hostedView.frame = uiView.bounds
      uiView.contentSize = hostedView.frame.size
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(hostingController: UIHostingController(rootView: self.content), onTap: self.onTap, isZoomed: $isZoomed)
  }

  // MARK: - Coordinator

  class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    var hostingController: UIHostingController<Content>
    var onTap: (() -> Void)?
    var onSwipe: ((Int) -> Void)?
    @Binding var isZoomed: Bool // Use the binding here

    init(hostingController: UIHostingController<Content>, onTap: (() -> Void)? = nil, isZoomed: Binding<Bool>) {
      self.hostingController = hostingController
      self.onTap = onTap
      _isZoomed = isZoomed
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
      hostingController.view
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
      isZoomed = scrollView.zoomScale > scrollView.minimumZoomScale
    }

    @objc func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
      onTap?()
    }

    /// Pages once the fingers lift from a mostly sideways swipe; a zoomed image pans instead.
    @objc func handleTrackpadSwipe(_ gestureRecognizer: UIPanGestureRecognizer) {
      guard gestureRecognizer.state == .ended, let onSwipe, !isZoomed else { return }
      let translation = gestureRecognizer.translation(in: gestureRecognizer.view)
      let velocity = gestureRecognizer.velocity(in: gestureRecognizer.view)
      guard abs(translation.x) > abs(translation.y), abs(translation.x) > 60 || abs(velocity.x) > 400 else { return }
      // Fingers moving left bring in the next image, as a touch swipe does.
      onSwipe(translation.x < 0 ? 1 : -1)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
      true
    }

    @objc func handleDoubleTap(_ gestureRecognizer: UITapGestureRecognizer) {
      if let scrollView = gestureRecognizer.view as? UIScrollView {
        if scrollView.zoomScale == 1 {
          let tapLocation = gestureRecognizer.location(in: scrollView)
          // CGPoint(x: tapLocation.x / 1.35, y: tapLocation.y * 0.87) -- Magic numbers go brrrr
          let zoomRect = CGRect(origin: CGPoint(x: tapLocation.x / 1.35, y: tapLocation.y * 0.87), size: CGSize(width: 100, height: 100))
          scrollView.zoom(to: zoomRect, animated: true)
        } else {
          scrollView.setZoomScale(1, animated: true)
        }
      }
    }

//        func scrollViewDidScroll(_ scrollView: UIScrollView) {
//            let offsetY = scrollView.contentOffset.y
//            let contentHeight = scrollView.contentSize.height
//            let scrollViewHeight = scrollView.bounds.height
//            print()
//            print(offsetY)
//
//            if offsetY < (contentHeight / 2) || offsetY > (contentHeight / 2) {
//                scrollView.setContentOffset(CGPoint(x: 0, y: contentHeight - scrollViewHeight), animated: false)
//            }
//        }
  }
}
