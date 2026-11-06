//
//  ReadableWidth.swift
//  Helio
//
//  Wide columns (a Mac window, full-screen iPad) keep feeds, posts and lists at a reading
//  width instead of stretching rows across the whole column.
//

import SwiftUI

enum ReadableWidth {
  /// The widest rows get.
  static let max: CGFloat = 700

  /// The width content gets in `column`, of which `visibleWidth` is inside the window's safe
  /// area. A column across the open iPhone Duo's hinge uses its whole width: a centered column
  /// would straddle the hinge. A pane on one side of it is capped like any other column.
  static func contentWidth(column: CGRect, visibleWidth: CGFloat, division: CGRect?) -> CGFloat {
    let spansHinge = division.map { column.minX < $0.midX && $0.midX < column.maxX } ?? false
    return spansHinge ? visibleWidth : min(visibleWidth, max)
  }
}

private struct PaneHingeEdgesKey: EnvironmentKey {
  static let defaultValue: Edge.Set = []
}

extension EnvironmentValues {
  /// The side of an open iPhone Duo pane that's at the hinge (`SubredditsStack`), whose safe-area
  /// inset its screens ignore. A navigation stack in a pane gets the window's inset on that side
  /// too, such as the side tab bar's in the feed pane, though nothing of the system's is there.
  var paneHingeEdges: Edge.Set {
    get { self[PaneHingeEdgesKey.self] }
    set { self[PaneHingeEdgesKey.self] = newValue }
  }
}

private struct ReadableInsetKey: EnvironmentKey {
  static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
  /// How far `readableWidth()` insets content on each side to keep it at the column's
  /// `contentWidth`.
  var readableInset: CGFloat {
    get { self[ReadableInsetKey.self] }
    set { self[ReadableInsetKey.self] = newValue }
  }
}

private struct ColumnContentWidth: ViewModifier {
  @State private var frame: CGRect = .zero

  func body(content: Content) -> some View {
    let metrics = WindowMetrics.shared
    // A column can run under the folded iPhone Duo's side tab bar while its content stops at
    // the window's safe area, so only the part inside that counts.
    let visible = frame.intersection(metrics.contentFrame).width
    let width = frame.width > 0 ? (visible > 0 ? visible : frame.width) : metrics.contentWidth
    let contentWidth = ReadableWidth.contentWidth(column: frame.width > 0 ? frame : metrics.contentFrame, visibleWidth: width, division: metrics.divisionFrame)
    content
      .environment(\.contentWidth, contentWidth)
      .environment(\.readableInset, ((width - contentWidth) / 2).rounded(.down))
      // Fill the column so this measures it rather than the content.
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
  }
}

extension View {
  /// Measures the column (or window) this fills and gives what's inside its reading width as
  /// `contentWidth`, which posts are laid out for. Apply to each navigation stack.
  func columnContentWidth() -> some View {
    modifier(ColumnContentWidth())
  }

  /// Insets a screen to its column's reading width. Lists still scroll, and draw their
  /// background, across the whole column. Apply to each screen in a `columnContentWidth()` stack.
  func readableWidth() -> some View {
    modifier(ReadableInsetModifier())
  }

  /// Lays a screen in an open iPhone Duo pane out to the hinge, past the safe-area inset its stack
  /// gets on that side (`paneHingeEdges`). Otherwise a list there would inset its rows by the side
  /// tab bar's width while they're laid out for the whole pane, and they'd run off its other edge.
  /// Apply to each screen in a pane's stack.
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
