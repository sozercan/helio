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
final class WindowMetrics {
  static let shared = WindowMetrics()

  /// The window's full size, including the safe area.
  private(set) var size: CGSize
  /// Regular width: unfolded iPhone Duo, full-screen iPad, Mac. Compact: iPhone, folded Duo,
  /// narrow iPad split.
  private(set) var isWide: Bool
  private(set) var displayScale: CGFloat

  private init() {
    let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen
    size = screen?.bounds.size ?? CGSize(width: 390, height: 844)
    isWide = UIDevice.current.userInterfaceIdiom != .phone
    displayScale = screen?.scale ?? 3
  }

  func update(size: CGSize? = nil, horizontalSizeClass: UserInterfaceSizeClass? = nil, displayScale: CGFloat? = nil) {
    if let size, size.width > 0, size.height > 0, size != self.size { self.size = size }
    if let horizontalSizeClass {
      let wide = horizontalSizeClass == .regular
      if wide != isWide { isWide = wide }
    }
    if let displayScale, displayScale > 0, displayScale != self.displayScale { self.displayScale = displayScale }
  }
}

/// Wide (regular width) window layout. Replaces device-idiom checks, which can't tell an
/// unfolded iPhone Duo or a narrow iPad window apart.
var isWideLayout: Bool { WindowMetrics.shared.isWide }

private struct WindowMetricsReader: ViewModifier {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.displayScale) private var displayScale

  func body(content: Content) -> some View {
    content
      .background {
        // The root view is laid out inside the safe area, and `ignoresSafeArea` doesn't reach
        // every inset (folded iPhone Duo's status column), so add the insets back.
        Color.clear
          .onGeometryChange(for: CGSize.self) { proxy in
            let insets = proxy.safeAreaInsets
            return CGSize(width: proxy.size.width + insets.leading + insets.trailing, height: proxy.size.height + insets.top + insets.bottom)
          } action: { WindowMetrics.shared.update(size: $0) }
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
