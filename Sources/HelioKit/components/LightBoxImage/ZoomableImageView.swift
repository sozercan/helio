import Foundation
import SwiftUI
import UIKit

struct ZoomableScrollView<Content: View>: UIViewRepresentable {
  static var doubleTapZoomScale: CGFloat {
    2.5
  }

  static func doubleTapZoomRect(
    in bounds: CGRect,
    centeredAt point: CGPoint,
    scale: CGFloat = doubleTapZoomScale,
    minimumZoomScale: CGFloat = 1,
    maximumZoomScale: CGFloat = 20,
  ) -> CGRect {
    let clampedScale = max(minimumZoomScale, min(scale, maximumZoomScale))
    guard bounds.width > 0, bounds.height > 0, clampedScale > 0 else {
      return bounds
    }
    let width = bounds.width / clampedScale
    let height = bounds.height / clampedScale
    let maxOriginX = bounds.maxX - width
    let maxOriginY = bounds.maxY - height
    let originX = min(max(point.x - width / 2, bounds.minX), maxOriginX)
    let originY = min(max(point.y - height / 2, bounds.minY), maxOriginY)
    return CGRect(x: originX, y: originY, width: width, height: height)
  }

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

    if !isZoomed, uiView.zoomScale > uiView.minimumZoomScale {
      uiView.setZoomScale(uiView.minimumZoomScale, animated: false)
    }

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
      let zoomed = scrollView.zoomScale > scrollView.minimumZoomScale
      if isZoomed != zoomed {
        isZoomed = zoomed
      }
    }

    @objc func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
      onTap?()
    }

    @objc func handleDoubleTap(_ gestureRecognizer: UITapGestureRecognizer) {
      guard let scrollView = gestureRecognizer.view as? UIScrollView else { return }
      if scrollView.zoomScale <= scrollView.minimumZoomScale {
        let tapLocation = gestureRecognizer.location(in: hostingController.view)
        let zoomRect = ZoomableScrollView.doubleTapZoomRect(
          in: hostingController.view.bounds,
          centeredAt: tapLocation,
          minimumZoomScale: scrollView.minimumZoomScale,
          maximumZoomScale: scrollView.maximumZoomScale,
        )
        scrollView.zoom(to: zoomRect, animated: true)
      } else {
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
      }
    }
  }
}
