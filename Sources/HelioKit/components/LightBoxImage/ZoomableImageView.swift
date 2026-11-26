import Foundation
import SwiftUI
import UIKit

struct ZoomableScrollView<Content: View>: UIViewRepresentable {
  private var content: Content
  private var onTap: (() -> Void)?
  private var onSwipe: ((Int) -> Void)?
  private var onHold: ((LightBoxScrub) -> Void)?
  @Binding var isZoomed: Bool

  init(onTap: (() -> Void)? = nil, onSwipe: ((Int) -> Void)? = nil, onHold: ((LightBoxScrub) -> Void)? = nil, isZoomed: Binding<Bool>, @ViewBuilder content: () -> Content) {
    self.content = content()
    self.onTap = onTap
    self.onSwipe = onSwipe
    self.onHold = onHold
    self._isZoomed = isZoomed
  }

  func makeUIView(context: Context) -> UIScrollView {
    let scrollView = UIScrollView()
    scrollView.contentInsetAdjustmentBehavior = .never
    scrollView.delegate = context.coordinator
    scrollView.maximumZoomScale = 20
    scrollView.minimumZoomScale = 1
    scrollView.bouncesZoom = true
    scrollView.bounces = true
    scrollView.showsVerticalScrollIndicator = false
    scrollView.showsHorizontalScrollIndicator = false

    context.coordinator.hostingController.safeAreaRegions = []
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

    let gestures = context.coordinator.gestures
    gestures.onSwipe = onSwipe
    gestures.onHold = onHold
    gestures.isZoomed = { [weak scrollView] in (scrollView?.zoomScale ?? 1) > (scrollView?.minimumZoomScale ?? 1) }
    gestures.install(on: scrollView)
    if let hold = gestures.hold {
      tapGesture.require(toFail: hold)
    }

    return scrollView
  }

  func updateUIView(_ uiView: UIScrollView, context: Context) {
    context.coordinator.hostingController.rootView = self.content
    context.coordinator.gestures.onSwipe = onSwipe
    context.coordinator.gestures.onHold = onHold
    assert(context.coordinator.hostingController.view.superview == uiView)

    if uiView.zoomScale == uiView.minimumZoomScale {
      let hostedView = context.coordinator.hostingController.view!
      hostedView.frame = uiView.bounds
      uiView.contentSize = hostedView.frame.size
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(hostingController: UIHostingController(rootView: self.content), onTap: self.onTap, isZoomed: $isZoomed)
  }

  class Coordinator: NSObject, UIScrollViewDelegate {
    var hostingController: UIHostingController<Content>
    var onTap: (() -> Void)?
    let gestures = LightBoxGestures()
    @Binding var isZoomed: Bool

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

    @objc func handleDoubleTap(_ gestureRecognizer: UITapGestureRecognizer) {
      if let scrollView = gestureRecognizer.view as? UIScrollView {
        if scrollView.zoomScale == 1 {
          let tapLocation = gestureRecognizer.location(in: scrollView)
          let zoomRect = CGRect(origin: CGPoint(x: tapLocation.x / 1.35, y: tapLocation.y * 0.87), size: CGSize(width: 100, height: 100))
          scrollView.zoom(to: zoomRect, animated: true)
        } else {
          scrollView.setZoomScale(1, animated: true)
        }
      }
    }
  }
}
