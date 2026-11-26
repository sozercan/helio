import SwiftUI

enum ReadableWidth {
  static let max: CGFloat = 700

  static func contentWidth(column: CGRect, visibleWidth: CGFloat, division: CGRect?) -> CGFloat {
    let spansHinge = division.map { column.minX < $0.midX && $0.midX < column.maxX } ?? false
    return spansHinge ? visibleWidth : min(visibleWidth, max)
  }
}

private struct PaneHingeEdgesKey: EnvironmentKey {
  static let defaultValue: Edge.Set = []
}

extension EnvironmentValues {
  var paneHingeEdges: Edge.Set {
    get { self[PaneHingeEdgesKey.self] }
    set { self[PaneHingeEdgesKey.self] = newValue }
  }
}

private struct ReadableInsetKey: EnvironmentKey {
  static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
  var readableInset: CGFloat {
    get { self[ReadableInsetKey.self] }
    set { self[ReadableInsetKey.self] = newValue }
  }
}

private struct ColumnContentWidth: ViewModifier {
  @State private var frame: CGRect = .zero

  func body(content: Content) -> some View {
    let metrics = WindowMetrics.shared
    let visible = frame.intersection(metrics.contentFrame).width
    let width = frame.width > 0 ? (visible > 0 ? visible : frame.width) : metrics.contentWidth
    let contentWidth = ReadableWidth.contentWidth(column: frame.width > 0 ? frame : metrics.contentFrame, visibleWidth: width, division: metrics.divisionFrame)
    content
      .environment(\.contentWidth, contentWidth)
      .environment(\.readableInset, ((width - contentWidth) / 2).rounded(.down))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
  }
}

extension View {
  func columnContentWidth() -> some View {
    modifier(ColumnContentWidth())
  }

  func readableWidth() -> some View {
    modifier(ReadableInsetModifier())
  }

  func ignoresPaneHingeInsets() -> some View {
    modifier(PaneHingeInsetsModifier())
  }
}

private struct PaneHingeInsetsModifier: ViewModifier {
  @Environment(\.paneHingeEdges) private var edges

  func body(content: Content) -> some View {
    content.ignoresSafeArea(.container, edges: edges)
  }
}

private struct ReadableInsetModifier: ViewModifier {
  @Environment(\.readableInset) private var inset

  func body(content: Content) -> some View {
    content.safeAreaPadding(.horizontal, inset)
  }
}
