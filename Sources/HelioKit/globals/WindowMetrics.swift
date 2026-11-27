import SwiftUI
import UIKit

@Observable
final class WindowMetrics: @unchecked Sendable {
  static let shared = WindowMetrics()

  @ObservationIgnored private let lock = NSLock()
  @ObservationIgnored private var _size: CGSize
  @ObservationIgnored private var _contentWidth: CGFloat
  @ObservationIgnored private var _contentFrame: CGRect
  @ObservationIgnored private var _isWide: Bool
  @ObservationIgnored private var _displayScale: CGFloat
  @ObservationIgnored private var _divisionFrame: CGRect?

  var size: CGSize {
    access(keyPath: \.size)
    return lock.withLock { _size }
  }

  var contentWidth: CGFloat {
    access(keyPath: \.contentWidth)
    return lock.withLock { _contentWidth }
  }

  var contentFrame: CGRect {
    access(keyPath: \.contentFrame)
    return lock.withLock { _contentFrame }
  }

  var isWide: Bool {
    access(keyPath: \.isWide)
    return lock.withLock { _isWide }
  }

  var displayScale: CGFloat {
    access(keyPath: \.displayScale)
    return lock.withLock { _displayScale }
  }

  var divisionFrame: CGRect? {
    access(keyPath: \.divisionFrame)
    return lock.withLock { _divisionFrame }
  }

  private init() {
    let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen
    _size = screen?.bounds.size ?? CGSize(width: 390, height: 844)
    _contentWidth = _size.width
    _contentFrame = CGRect(origin: .zero, size: _size)
    _isWide = _size.width >= 700
    _displayScale = screen?.scale ?? 3
  }

  func update(size: CGSize? = nil, contentWidth: CGFloat? = nil, contentFrame: CGRect? = nil, divisionFrame: CGRect?? = nil, horizontalSizeClass: UserInterfaceSizeClass? = nil, displayScale: CGFloat? = nil) {
    if let divisionFrame, divisionFrame != self.divisionFrame {
      withMutation(keyPath: \.divisionFrame) { lock.withLock { _divisionFrame = divisionFrame } }
    }
    if let size, size.width > 0, size.height > 0, size != self.size {
      withMutation(keyPath: \.size) { lock.withLock { _size = size } }
    }
    if let contentWidth, contentWidth > 0, contentWidth != self.contentWidth {
      withMutation(keyPath: \.contentWidth) { lock.withLock { _contentWidth = contentWidth } }
    }
    if let contentFrame, contentFrame.width > 0, contentFrame != self.contentFrame {
      withMutation(keyPath: \.contentFrame) { lock.withLock { _contentFrame = contentFrame } }
    }
    if let horizontalSizeClass {
      let wide = horizontalSizeClass == .regular
      if wide != isWide {
        withMutation(keyPath: \.isWide) { lock.withLock { _isWide = wide } }
      }
    }
    if let displayScale, displayScale > 0, displayScale != self.displayScale {
      withMutation(keyPath: \.displayScale) { lock.withLock { _displayScale = displayScale } }
    }
  }
}

var isWideLayout: Bool {
  WindowMetrics.shared.isWide
}

private struct WindowMetricsReader: ViewModifier {
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.displayScale) private var displayScale

  private struct Geometry: Equatable {
    var size: CGSize
    var contentWidth: CGFloat
    var contentFrame: CGRect
    var divisionFrame: CGRect?
  }

  private static func divisionFrame(_ proxy: GeometryProxy) -> CGRect? {
    #if compiler(>=6.4)
      if #available(iOS 27.1, *) {
        return proxy.reservedRegions(kind: .division, options: .includeInactive).first?.frame
      }
    #endif
    return nil
  }

  func body(content: Content) -> some View {
    content
      .background {
        Color.clear
          .onGeometryChange(for: Geometry.self) { proxy in
            let insets = proxy.safeAreaInsets
            let size = CGSize(width: proxy.size.width + insets.leading + insets.trailing, height: proxy.size.height + insets.top + insets.bottom)
            let frame = proxy.frame(in: .global)
            return Geometry(size: size, contentWidth: proxy.size.width, contentFrame: frame, divisionFrame: Self.divisionFrame(proxy)?.offsetBy(dx: frame.minX, dy: frame.minY))
          } action: { WindowMetrics.shared.update(size: $0.size, contentWidth: $0.contentWidth, contentFrame: $0.contentFrame, divisionFrame: .some($0.divisionFrame)) }
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
  func readsWindowMetrics() -> some View {
    modifier(WindowMetricsReader())
  }
}
