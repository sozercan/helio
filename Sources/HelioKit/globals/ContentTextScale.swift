//
//  ContentTextScale.swift
//  Helio
//

import Defaults
import SwiftUI
import Synchronization
import UIKit

/// Scales content text (post titles and bodies, comments, their meta lines and link previews)
/// with the system text size, the way `UIFontMetrics` scales a text style. Theme sizes are the
/// sizes at the default text size, so nothing changes there. Controls and icons keep their sizes.
///
/// Settings > Appearance > Text Size moves content text a few steps from the system size
/// (`adjusted(_:by:)`); on Mac, which has no Dynamic Type, it's the only text size control.
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

  /// The steps Text Size can move content text from the system size: down to the smallest
  /// size, and up to two accessibility sizes past the largest standard one.
  static let adjustmentRange = -3 ... 5

  /// The size content text is laid out for: the system's, `adjustment` steps smaller or larger,
  /// within Dynamic Type's sizes. Mac Catalyst has no Dynamic Type, so there it starts from
  /// the default size, the one the Mac layout was made for.
  static func adjusted(_ system: DynamicTypeSize, by adjustment: Int) -> DynamicTypeSize {
    #if targetEnvironment(macCatalyst)
      let system = DynamicTypeSize.large
    #endif
    let sizes = DynamicTypeSize.allCases
    guard let index = sizes.firstIndex(of: system) else { return system }
    let step = min(max(adjustment, adjustmentRange.lowerBound), adjustmentRange.upperBound)
    return sizes[min(max(index + step, 0), sizes.count - 1)]
  }

  /// `size`, a size at the default text size, scaled for `dynamicTypeSize` like `role`.
  static func size(_ size: CGFloat, relativeTo role: Role = .body, dynamicTypeSize: DynamicTypeSize = ContentTextScale.dynamicTypeSize) -> CGFloat {
    let capped = min(dynamicTypeSize, role.maximum)
    guard capped != .large else { return size }
    #if targetEnvironment(macCatalyst)
      // Mac Catalyst has no Dynamic Type, and `UIFontMetrics` doesn't scale there: follow the
      // body style's iOS sizes instead.
      return (size * macScale(capped) * 2).rounded() / 2
    #else
      let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(capped))
      return UIFontMetrics(forTextStyle: role.textStyle).scaledValue(for: size, compatibleWith: traits)
    #endif
  }

  /// How much `size` scales iOS's body text from the default size, 17 points.
  static func macScale(_ size: DynamicTypeSize) -> CGFloat {
    let body: CGFloat = switch size {
    case .xSmall: 14
    case .small: 15
    case .medium: 16
    case .large: 17
    case .xLarge: 19
    case .xxLarge: 21
    case .xxxLarge: 23
    case .accessibility1: 28
    case .accessibility2: 33
    case .accessibility3: 40
    case .accessibility4: 47
    case .accessibility5: 53
    @unknown default: 17
    }
    return body / 17
  }

  /// A system font of `size` (at the default text size), scaled like `role`.
  static func font(ofSize size: CGFloat, weight: UIFont.Weight = .regular, relativeTo role: Role = .body, dynamicTypeSize: DynamicTypeSize = ContentTextScale.dynamicTypeSize) -> UIFont {
    UIFont.systemFont(ofSize: self.size(size, relativeTo: role, dynamicTypeSize: dynamicTypeSize), weight: weight)
  }
}

private struct ContentFontModifier: ViewModifier {
  @Environment(\.contentTypeSize) private var dynamicTypeSize
  let size: CGFloat
  let weight: Font.Weight
  let design: Font.Design
  let role: ContentTextScale.Role

  func body(content: Content) -> some View {
    content.font(.system(size: ContentTextScale.size(size, relativeTo: role, dynamicTypeSize: dynamicTypeSize), weight: weight, design: design))
  }
}

private struct ContentTypeSizeKey: EnvironmentKey {
  static let defaultValue: DynamicTypeSize = .large
}

extension EnvironmentValues {
  /// The text size content is laid out for: the system's, adjusted by Settings > Appearance >
  /// Text Size (`ContentTextScale.adjusted`). Read this, not `dynamicTypeSize`, for content text.
  var contentTypeSize: DynamicTypeSize {
    get { self[ContentTypeSizeKey.self] }
    set { self[ContentTypeSizeKey.self] = newValue }
  }
}

private struct TrackContentTextScale: ViewModifier {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Default(.contentTextSizeAdjustment) private var adjustment

  func body(content: Content) -> some View {
    let size = ContentTextScale.adjusted(dynamicTypeSize, by: adjustment)
    content
      .environment(\.contentTypeSize, size)
      .onChange(of: size, initial: true) { _, size in
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

  /// Keeps `ContentTextScale` and `contentTypeSize` on the window's text size and the Text Size
  /// setting. Applied at the root, before feeds fetch and measure their first posts.
  func trackContentTextScale() -> some View {
    modifier(TrackContentTextScale())
  }
}
