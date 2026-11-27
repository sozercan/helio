import Defaults
import SwiftUI
import Synchronization
import UIKit

enum ContentTextScale {
  enum Role {
    case title
    case body
    case detail
    case meta

    var textStyle: UIFont.TextStyle {
      switch self {
      case .title: .headline
      case .body: .body
      case .detail: .subheadline
      case .meta: .footnote
      }
    }

    var maximum: DynamicTypeSize {
      self == .meta ? .accessibility2 : .accessibility5
    }
  }

  private static let current = Mutex<DynamicTypeSize>(.large)

  static var dynamicTypeSize: DynamicTypeSize {
    get { current.withLock { $0 } }
    set { current.withLock { $0 = newValue } }
  }

  static let adjustmentRange = -3 ... 5

  static func adjusted(_ system: DynamicTypeSize, by adjustment: Int) -> DynamicTypeSize {
    #if targetEnvironment(macCatalyst)
      let system = DynamicTypeSize.large
    #endif
    let sizes = DynamicTypeSize.allCases
    guard let index = sizes.firstIndex(of: system) else { return system }
    let step = min(max(adjustment, adjustmentRange.lowerBound), adjustmentRange.upperBound)
    return sizes[min(max(index + step, 0), sizes.count - 1)]
  }

  static func size(_ size: CGFloat, relativeTo role: Role = .body, dynamicTypeSize: DynamicTypeSize = ContentTextScale.dynamicTypeSize) -> CGFloat {
    let capped = min(dynamicTypeSize, role.maximum)
    guard capped != .large else { return size }
    #if targetEnvironment(macCatalyst)
      return (size * macScale(capped) * 2).rounded() / 2
    #else
      let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(capped))
      return UIFontMetrics(forTextStyle: role.textStyle).scaledValue(for: size, compatibleWith: traits)
    #endif
  }

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
  func contentFont(_ size: CGFloat, _ weight: Font.Weight = .regular, design: Font.Design = .default, relativeTo role: ContentTextScale.Role = .body) -> some View {
    modifier(ContentFontModifier(size: size, weight: weight, design: design, role: role))
  }

  func trackContentTextScale() -> some View {
    modifier(TrackContentTextScale())
  }
}
