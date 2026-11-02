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
  static let max: CGFloat = MacIdiom.size(700)

  /// The width content gets in a column `width` wide. The open iPhone Duo uses its whole width:
  /// a centered column would straddle the hinge.
  static func contentWidth(column width: CGFloat, hasDivision: Bool) -> CGFloat {
    hasDivision ? width : min(width, max)
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
    let contentWidth = ReadableWidth.contentWidth(column: width, hasDivision: metrics.divisionFrame != nil)
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
}

private struct ReadableInsetModifier: ViewModifier {
  @Environment(\.readableInset) private var inset

  func body(content: Content) -> some View {
    content.safeAreaPadding(.horizontal, inset)
  }
}
