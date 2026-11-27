import CoreGraphics
import SwiftUI
import Testing
import UIKit
@testable import HelioKit

struct LightBoxZoomTests {
  @Test func doubleTapZoomRectCentersAroundTapPoint() {
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 800)
    let rect = ZoomableScrollView<EmptyView>.doubleTapZoomRect(in: bounds, centeredAt: CGPoint(x: 200, y: 400), scale: 2.5)
    #expect(rect.width == 160)
    #expect(rect.height == 320)
    #expect(rect.midX == 200)
    #expect(rect.midY == 400)
  }

  @Test func doubleTapZoomRectClampsToContentBoundsAtEdges() {
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 800)

    let topLeft = ZoomableScrollView<EmptyView>.doubleTapZoomRect(in: bounds, centeredAt: CGPoint(x: 10, y: 15), scale: 2.5)
    #expect(topLeft.origin == .zero)
    #expect(topLeft.size == CGSize(width: 160, height: 320))

    let bottomRight = ZoomableScrollView<EmptyView>.doubleTapZoomRect(in: bounds, centeredAt: CGPoint(x: 395, y: 790), scale: 2.5)
    #expect(bottomRight.maxX == bounds.maxX)
    #expect(bottomRight.maxY == bounds.maxY)
    #expect(bottomRight.size == CGSize(width: 160, height: 320))
  }

  @Test func doubleTapZoomRectRespectsScaleLimitsAndEmptyBounds() {
    let bounds = CGRect(x: 0, y: 0, width: 300, height: 600)
    let clampedToMax = ZoomableScrollView<EmptyView>.doubleTapZoomRect(in: bounds, centeredAt: CGPoint(x: 150, y: 300), scale: 10, minimumZoomScale: 1, maximumZoomScale: 2)
    #expect(clampedToMax.size == CGSize(width: 150, height: 300))

    let clampedToMin = ZoomableScrollView<EmptyView>.doubleTapZoomRect(in: bounds, centeredAt: CGPoint(x: 150, y: 300), scale: 0.5, minimumZoomScale: 1, maximumZoomScale: 20)
    #expect(clampedToMin == bounds)

    let empty = ZoomableScrollView<EmptyView>.doubleTapZoomRect(in: .zero, centeredAt: CGPoint(x: 50, y: 50), scale: 2.5)
    #expect(empty == .zero)
  }

  @Test func zoomStateScopesPerPageAndResetsInactivePages() {
    var state = LightBoxZoomState()
    state.setZoomed(true, at: 0)
    #expect(state.isZoomed(at: 0))
    #expect(!state.isZoomed(at: 1))

    state.activePageDidChange(to: 1)
    #expect(!state.isZoomed(at: 0))
    #expect(!state.isZoomed(at: 1))

    state.setZoomed(true, at: 1)
    state.activePageDidChange(to: 1)
    #expect(state.isZoomed(at: 1))
  }

  private final class FakeTransitioningController: UIViewController {
    var dismissing = false

    override var isBeingDismissed: Bool {
      dismissing
    }
  }

  @MainActor
  @Test func shareUtilsWaitsUntilTopControllerStopsTransitioning() async {
    let controller = FakeTransitioningController()
    controller.dismissing = true
    var yields = 0
    var sleeps = 0
    let ready = await ShareUtils.waitForPresentationReady(
      resolveTop: { controller },
      maxAttempts: 5,
      yield: { yields += 1 },
      sleep: {
        sleeps += 1
        if sleeps == 2 {
          controller.dismissing = false
        }
      },
    )
    #expect(ready)
    #expect(yields == 1)
    #expect(sleeps == 2)
    #expect(!ShareUtils.isTransitioning(controller))
  }

  @MainActor
  @Test func shareUtilsReturnsFalseWhenTransitionNeverFinishes() async {
    let controller = FakeTransitioningController()
    controller.dismissing = true
    var sleeps = 0
    let ready = await ShareUtils.waitForPresentationReady(
      resolveTop: { controller },
      maxAttempts: 3,
      yield: {},
      sleep: { sleeps += 1 },
    )
    #expect(!ready)
    #expect(sleeps == 3)
  }

  @MainActor
  @Test func shareUtilsReturnsFalseWhenNoTopControllerExists() async {
    let ready = await ShareUtils.waitForPresentationReady(
      resolveTop: { nil },
      maxAttempts: 3,
      yield: {},
      sleep: {},
    )
    #expect(!ready)
  }
}
