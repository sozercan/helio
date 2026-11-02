//
//  ContentTextScale.swift
//  Helio
//

import SwiftUI
import Synchronization
import UIKit

/// Scales content text (post titles and bodies, comments, their meta lines and link previews)
/// with the system text size, the way `UIFontMetrics` scales a text style. Theme sizes are the
/// sizes at the default text size, so nothing changes there. Controls and icons keep their sizes.
///
/// Feed titles are measured off the main thread, so the current size lives here, set from the
/// SwiftUI environment (`trackContentTextScale()`), instead of being read from a trait collection.
enum ContentTextScale {
  /// What a piece of content text is, which decides how it scales.
  enum Role {
    /// Post titles.
    case title
    /// Post and comment bodies, and other wrapping text.
    case body
    /// Secondary text in its own space, like a link preview's description.
    case detail
    /// Author, subreddit, score and age lines and tags. They share a row with buttons.
    case meta

    var textStyle: UIFont.TextStyle {
      switch self {
      case .title: .headline
      case .body: .body
      case .detail: .subheadline
      case .meta: .footnote
      }
    }

    /// Titles and bodies wrap, so they follow the system size all the way. Meta lines stop at
    /// AX2: past it, a post's numbers no longer fit beside its "•••" and vote buttons on an iPhone.
    var maximum: DynamicTypeSize {
      self == .meta ? .accessibility2 : .accessibility5
    }
  }

  private static let current = Mutex<DynamicTypeSize>(.large)

  /// The system text size content is laid out for.
  static var dynamicTypeSize: DynamicTypeSize {
    get { current.withLock { $0 } }
    set { current.withLock { $0 = newValue } }
  }

  /// `size`, a size at the default text size, scaled for `dynamicTypeSize` like `role`.
  static func size(_ size: CGFloat, relativeTo role: Role = .body, dynamicTypeSize: DynamicTypeSize = ContentTextScale.dynamicTypeSize) -> CGFloat {
    #if targetEnvironment(macCatalyst)
      // Mac Catalyst has no Dynamic Type: keep the sizes the Mac layout was made for.
      return size
    #else
      let capped = min(dynamicTypeSize, role.maximum)
      guard capped != .large else { return size }
      let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(capped))
      return UIFontMetrics(forTextStyle: role.textStyle).scaledValue(for: size, compatibleWith: traits)
    #endif
  }

  /// A system font of `size` (at the default text size), scaled like `role`.
  static func font(ofSize size: CGFloat, weight: UIFont.Weight = .regular, relativeTo role: Role = .body, dynamicTypeSize: DynamicTypeSize = ContentTextScale.dynamicTypeSize) -> UIFont {
    UIFont.systemFont(ofSize: self.size(size, relativeTo: role, dynamicTypeSize: dynamicTypeSize), weight: weight)
  }
}

private struct ContentFontModifier: ViewModifier {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let size: CGFloat
  let weight: Font.Weight
  let design: Font.Design
  let role: ContentTextScale.Role

  func body(content: Content) -> some View {
    content.font(.system(size: ContentTextScale.size(size, relativeTo: role, dynamicTypeSize: dynamicTypeSize), weight: weight, design: design))
  }
}

private struct TrackContentTextScale: ViewModifier {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  func body(content: Content) -> some View {
    content.onChange(of: dynamicTypeSize, initial: true) { _, size in
      ContentTextScale.dynamicTypeSize = size
    }
  }
}

extension View {
  /// `fontSize` for content text: `size` at the default text size, scaled with Dynamic Type
  /// for its `role` (see `ContentTextScale`).
  func contentFont(_ size: CGFloat, _ weight: Font.Weight = .regular, design: Font.Design = .default, relativeTo role: ContentTextScale.Role = .body) -> some View {
    modifier(ContentFontModifier(size: size, weight: weight, design: design, role: role))
  }

  /// Keeps `ContentTextScale` on the window's text size. Applied at the root, before feeds
  /// fetch and measure their first posts.
  func trackContentTextScale() -> some View {
    modifier(TrackContentTextScale())
  }
}
