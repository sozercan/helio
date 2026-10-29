//
//  WindowMetrics.swift
//  winston
//
//  The window's current size and width class. The window can change size while the app
//  runs: folding or unfolding iPhone Duo, iPad multitasking, resizing a Mac window. So
//  layout reads these instead of UIScreen.main or the device idiom. Views that read them
//  in `body` are re-rendered when they change.
//

import SwiftUI
import UIKit

@Observable
final class WindowMetrics: @unchecked Sendable {
  static let shared = WindowMetrics()

  // Background work reads these (post setup, image processing) while the main thread updates
  // them, so they live behind a lock and report access and changes to Observation by hand.
  @ObservationIgnored private let lock = NSLock()
  @ObservationIgnored private var _size: CGSize
  @ObservationIgnored private var _contentWidth: CGFloat
  @ObservationIgnored private var _isWide: Bool
  @ObservationIgnored private var _displayScale: CGFloat

  /// The window's full size, including the safe area.
  var size: CGSize {
    access(keyPath: \.size)
    return lock.withLock { _size }
  }
  /// The width inside the safe area, which full-width content gets: left of the folded
  /// iPhone Duo's side tab bar, for example.
  var contentWidth: CGFloat {
    access(keyPath: \.contentWidth)
    return lock.withLock { _contentWidth }
  }
  /// Regular width: unfolded iPhone Duo, full-screen iPad, Mac. Compact: iPhone, folded Duo,
  /// narrow iPad split.
  var isWide: Bool {
    access(keyPath: \.isWide)
    return lock.withLock { _isWide }
  }
  var displayScale: CGFloat {
    access(keyPath: \.displayScale)
    return lock.withLock { _displayScale }
  }

  private init() {
    let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen
    _size = screen?.bounds.size ?? CGSize(width: 390, height: 844)
    _contentWidth = _size.width
    _isWide = UIDevice.current.userInterfaceIdiom != .phone
    _displayScale = screen?.scale ?? 3
  }

  func update(size: CGSize? = nil, contentWidth: CGFloat? = nil, horizontalSizeClass: UserInterfaceSizeClass? = nil, displayScale: CGFloat? = nil) {
    if let size, size.width > 0, size.height > 0, size != self.size {
      withMutation(keyPath: \.size) { lock.withLock { _size = size } }
    }
    if let contentWidth, contentWidth > 0, contentWidth != self.contentWidth {
      withMutation(keyPath: \.contentWidth) { lock.withLock { _contentWidth = contentWidth } }
    }
    if let horizontalSizeClass {
      let wide = horizontalSizeClass == .regular
      if wide != isWide { withMutation(keyPath: \.isWide) { lock.withLock { _isWide = wide } } }
    }
    if let displayScale, displayScale > 0, displayScale != self.displayScale {
      withMutation(keyPath: \.displayScale) { lock.withLock { _displayScale = displayScale } }
    }
  }
}

/// Wide (regular width) window layout. Replaces device-idiom checks, which can't tell an
/// unfolded iPhone Duo or a narrow iPad window apart.
var isWideLayout: Bool { WindowMetrics.shared.isWide }

private struct WindowMetricsReader: ViewModifier {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.displayScale) private var displayScale

  private struct Geometry: Equatable {
    var size: CGSize
    var contentWidth: CGFloat
  }

  func body(content: Content) -> some View {
    content
      .background {
        // The root view is laid out inside the safe area, and `ignoresSafeArea` doesn't reach
        // every inset (folded iPhone Duo's status column), so add the insets back.
        Color.clear
          .onGeometryChange(for: Geometry.self) { proxy in
            let insets = proxy.safeAreaInsets
            let size = CGSize(width: proxy.size.width + insets.leading + insets.trailing, height: proxy.size.height + insets.top + insets.bottom)
            return Geometry(size: size, contentWidth: proxy.size.width)
          } action: { WindowMetrics.shared.update(size: $0.size, contentWidth: $0.contentWidth) }
      }
      .onChange(of: horizontalSizeClass, initial: true) { _, sizeClass in
        WindowMetrics.shared.update(horizontalSizeClass: sizeClass)
      }
      .onChange(of: displayScale, initial: true) { _, scale in
        WindowMetrics.shared.update(displayScale: scale)
      }
  }
}

extension View {
  /// Keeps `WindowMetrics` in sync with the window this view fills. Apply once, at the root.
  func readsWindowMetrics() -> some View {
    modifier(WindowMetricsReader())
  }
}
