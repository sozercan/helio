import Foundation
import SwiftUI
import Testing
import UIKit
@testable import HelioKit

struct ContentTextScaleTests {
  @Test(arguments: [ContentTextScale.Role.title, .body, .detail, .meta])
  func theDefaultTextSizeKeepsThemeSizes(role: ContentTextScale.Role) {
    for size: CGFloat in [12, 13, 15, 17, 19] {
      #expect(ContentTextScale.size(size, relativeTo: role, dynamicTypeSize: .large) == size)
    }
    let font = ContentTextScale.font(ofSize: 17, weight: .semibold, relativeTo: role, dynamicTypeSize: .large)
    #expect(font == UIFont.systemFont(ofSize: 17, weight: .semibold))
  }

  @Test func textGrowsWithTheTextSize() {
    let small = ContentTextScale.size(17, dynamicTypeSize: .xSmall)
    let large = ContentTextScale.size(17, dynamicTypeSize: .xxxLarge)
    let accessibility = ContentTextScale.size(17, dynamicTypeSize: .accessibility2)
    #expect(small < 17)
    #expect(large > 17)
    #expect(accessibility > large)
    // Titles and bodies wrap, so they keep growing.
    #expect(ContentTextScale.size(17, dynamicTypeSize: .accessibility5) > accessibility)
  }

  @Test func metaLinesStopGrowingAtTheirMaximum() {
    let maximum = ContentTextScale.size(13, relativeTo: .meta, dynamicTypeSize: ContentTextScale.Role.meta.maximum)
    #expect(maximum > ContentTextScale.size(13, relativeTo: .meta, dynamicTypeSize: .xxxLarge))
    #expect(ContentTextScale.size(13, relativeTo: .meta, dynamicTypeSize: .accessibility5) == maximum)
  }
}

@MainActor
struct DynamicTypeRelayoutTests {
  private var theme: HelioTheme {
    InMemoryTheme.shared.currentTheme
  }

  private func post() throws -> Post {
    let post = Post(id: postSampleData.id)
    post.data = postSampleData
    return post
  }

  @Test func aNewTextSizeMeasuresAndDrawsTheTitleAgain() throws {
    let saved = ContentTextScale.dynamicTypeSize
    defer { ContentTextScale.dynamicTypeSize = saved }
    ContentTextScale.dynamicTypeSize = .large

    let post = try post()
    post.setupHelioData(contentWidth: 400, theme: theme, fetchAvatar: false)
    let defaultTitle = try #require(post.helioData?.postDimensions.titleSize)
    let defaultAttr = try #require(post.helioData?.titleAttr)

    ContentTextScale.dynamicTypeSize = .accessibility2
    post.relayout(contentWidth: 400, theme: theme)
    let largeTitle = try #require(post.helioData?.postDimensions.titleSize)
    let largeAttr = try #require(post.helioData?.titleAttr)
    #expect(largeTitle.height > defaultTitle.height)
    #expect(largeAttr !== defaultAttr)
    let font = try #require(largeAttr.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
    #expect(font.pointSize > theme.postLinks.theme.titleText.size)
    #expect(post.helioData?.layoutDynamicTypeSize == .accessibility2)

    ContentTextScale.dynamicTypeSize = .large
    post.relayout(contentWidth: 400, theme: theme)
    #expect(post.helioData?.postDimensions.titleSize == defaultTitle)
  }

  @Test func theSameTextSizeKeepsTheLayout() throws {
    let saved = ContentTextScale.dynamicTypeSize
    defer { ContentTextScale.dynamicTypeSize = saved }
    ContentTextScale.dynamicTypeSize = .large

    let post = try post()
    post.setupHelioData(contentWidth: 400, theme: theme, fetchAvatar: false)
    post.helioData?.postDimensions = .zero
    post.relayout(contentWidth: 400, theme: theme)
    #expect(post.helioData?.postDimensions == .zero)
  }
}

struct AccessibilityLabelTests {
  @Test func spokenTimesSpellOutTheUnit() {
    let now = Int(Date().timeIntervalSince1970)
    #expect(spokenTimeSince(now - 60) == "1 minute ago")
    #expect(spokenTimeSince(now - 2 * 3600 - 5) == "2 hours ago")
    #expect(spokenTimeSince(now - 3 * 86400) == "3 days ago")
  }

  @Test func titlesReadTheirTags() {
    var data = postSampleData
    data.link_flair_text = "Discussion"
    data.over_18 = true
    #expect(postTitleAccessibilityLabel(data) == "\(data.title), NSFW, Discussion")
    data.link_flair_text = nil
    data.over_18 = false
    #expect(postTitleAccessibilityLabel(data) == data.title)
  }
}

struct IncreaseContrastTests {
  private func hex(_ color: UIColor, _ style: UIUserInterfaceStyle, _ contrast: UIAccessibilityContrast) -> String {
    let traits = UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceStyle: style), UITraitCollection(accessibilityContrast: contrast)])
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return String(format: "%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
  }

  @Test func secondaryTextDarkensWithIncreaseContrast() {
    let color = themeFontSecondary.uiColor()
    #expect(hex(color, .light, .normal) == "666666")
    #expect(hex(color, .light, .high) == "4D4D4D")
    #expect(hex(color, .dark, .normal) == "94969D")
    #expect(hex(color, .dark, .high) == "B4B6BC")
  }

  @Test func otherColorsDontChange() {
    let color = themeFontPrimary.uiColor()
    #expect(hex(color, .light, .high) == hex(color, .light, .normal))
    #expect(hex(color, .dark, .high) == hex(color, .dark, .normal))
  }
}
