import Foundation
import SwiftUI
import Testing
@testable import HelioKit

struct ThemePresetTests {
  /// WCAG contrast ratio between two opaque colors.
  private func contrast(_ a: ThemeColor, _ b: ThemeColor) -> Double {
    func luminance(_ color: ThemeColor) -> Double {
      let value = Int(color.hex, radix: 16) ?? 0
      let channels = [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF].map { channel -> Double in
        let c = Double(channel) / 255
        return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
      }
      return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }
    let (l1, l2) = (luminance(a), luminance(b))
    return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
  }

  @Test func presetsHaveDistinctIDsAndApolloComesFirst() {
    let ids = ThemePreset.all.map(\.id)
    #expect(Set(ids).count == ids.count)
    #expect(ids.first == defaultTheme.id)
    #expect(ThemePreset.all.allSatisfy { !$0.theme.metadata.name.isEmpty && !$0.theme.metadata.description.isEmpty })
  }

  /// A different `general` asks for a restart (`AppContent`), so presets never change it.
  @Test func presetsSwitchWithoutARestart() {
    #expect(ThemePreset.all.allSatisfy { $0.theme.general == defaultTheme.general })
  }

  @Test func trueBlackIsApolloInLightModeAndBlackInDarkMode() {
    let theme = ThemePreset.trueBlack.theme
    #expect(ThemePreset.trueBlack.modes == .dark)
    for colors in [theme.postLinks.theme.bg.color, theme.lists.foreground.color, theme.postLinks.divider.color, theme.comments.theme.bg] {
      #expect(colors.dark.hex == "000000")
    }
    #expect(theme.lists.bg == .color(.init(light: .init(hex: "F2F3F7"), dark: .init(hex: "000000"))))
    // Light mode is untouched.
    #expect(theme.postLinks.theme.bg.color.light == defaultTheme.postLinks.theme.bg.color.light)
    #expect(theme.postLinks.divider.color.light == defaultTheme.postLinks.divider.color.light)
    #expect(theme.lists.foreground.color.light == defaultTheme.lists.foreground.color.light)
    #expect(theme.comments.theme.indentColors == rainbowIndentColors)
  }

  @Test func highContrastTextReachesAAAAndSeparators3To1() {
    let theme = ThemePreset.highContrast.theme
    let cell = theme.postLinks.theme.bg.color
    let badge = theme.postLinks.theme.badge
    let texts = [theme.postLinks.theme.titleText.color, theme.postLinks.theme.bodyText.color, badge.authorText.color, badge.statsText.color, theme.comments.theme.bodyText.color, theme.comments.theme.badge.statsText.color]
    for text in texts {
      #expect(contrast(text.light, cell.light) >= 7)
      #expect(contrast(text.dark, cell.dark) >= 7)
    }
    // Flair text on its own background.
    #expect(contrast(badge.flairText.color.light, badge.flairBackground.light) >= 7)
    #expect(contrast(badge.flairText.color.dark, badge.flairBackground.dark) >= 7)
    // Separators on the cells, and list separators on Settings' rows too.
    for divider in [theme.lists.dividersColors, theme.comments.theme.indentColor] {
      #expect(contrast(divider.light, cell.light) >= 3)
      #expect(contrast(divider.dark, cell.dark) >= 3)
    }
    let row = theme.lists.foreground.color
    #expect(contrast(theme.lists.dividersColors.light, row.light) >= 3)
    #expect(contrast(theme.lists.dividersColors.dark, row.dark) >= 3)
    // The feed's divider between posts.
    let feedDivider = theme.postLinks.divider
    #expect(feedDivider.style != .no)
    #expect(contrast(feedDivider.color.light, cell.light) >= 3)
    #expect(contrast(feedDivider.color.dark, cell.dark) >= 3)
    // Comments' depth bars, which comments draw instead of `indentColor` while there are any.
    let comment = theme.comments.theme.bg
    #expect(!theme.comments.theme.indentColors.isEmpty)
    for bar in theme.comments.theme.indentColors {
      #expect(contrast(bar.light, comment.light) >= 3)
      #expect(contrast(bar.dark, comment.dark) >= 3)
    }
    // Stronger than Apollo's.
    #expect(contrast(theme.postLinks.theme.bodyText.color.light, cell.light) > contrast(defaultTheme.postLinks.theme.bodyText.color.light, cell.light))
  }

  @Test func theSelectedThemeIsABuiltInOneAnImportedOneOrApollo() {
    var imported = defaultTheme
    imported.id = "imported-theme"
    imported.metadata.name = "Imported"
    var settings = ThemesDefSettings(themesPresets: [imported], selectedThemeID: "imported-theme")
    #expect(HelioTheme.selected(in: settings) == imported)
    settings.selectedThemeID = ThemePreset.trueBlack.id
    #expect(HelioTheme.selected(in: settings) == ThemePreset.trueBlack.theme)
    settings.selectedThemeID = "deleted-theme"
    #expect(HelioTheme.selected(in: settings) == defaultTheme)
    #expect(HelioTheme.selected(in: ThemesDefSettings()) == defaultTheme)
  }
}

struct TextSizeAdjustmentTests {
  @Test func noAdjustmentKeepsTheSystemSize() {
    for size in DynamicTypeSize.allCases {
      #expect(ContentTextScale.adjusted(size, by: 0) == size)
    }
  }

  @Test func adjustmentMovesBySteps() {
    #expect(ContentTextScale.adjusted(.large, by: 1) == .xLarge)
    #expect(ContentTextScale.adjusted(.large, by: -3) == .xSmall)
    #expect(ContentTextScale.adjusted(.large, by: 5) == .accessibility2)
    #expect(ContentTextScale.adjusted(.xxxLarge, by: 2) == .accessibility2)
  }

  @Test func adjustmentStaysWithinDynamicTypeAndItsRange() {
    #expect(ContentTextScale.adjusted(.small, by: -3) == .xSmall)
    #expect(ContentTextScale.adjusted(.accessibility4, by: 5) == .accessibility5)
    // Out-of-range stored values are clamped to the slider's range.
    #expect(ContentTextScale.adjusted(.large, by: 40) == ContentTextScale.adjusted(.large, by: ContentTextScale.adjustmentRange.upperBound))
    #expect(ContentTextScale.adjusted(.large, by: -40) == .xSmall)
  }

  /// Mac Catalyst scales by iOS's body sizes, since `UIFontMetrics` doesn't scale there.
  @Test func macScaleFollowsTheBodySizes() {
    #expect(ContentTextScale.macScale(.large) == 1)
    let scales = DynamicTypeSize.allCases.map(ContentTextScale.macScale)
    #expect(scales == scales.sorted())
    #expect(Set(scales).count == scales.count)
    #expect(ContentTextScale.macScale(.xxxLarge) == 23.0 / 17)
  }

  @Test func largerTextScalesContentText() {
    let title = defaultTheme.postLinks.theme.titleText.size
    let smaller = ContentTextScale.size(title, relativeTo: .title, dynamicTypeSize: ContentTextScale.adjusted(.large, by: -2))
    let larger = ContentTextScale.size(title, relativeTo: .title, dynamicTypeSize: ContentTextScale.adjusted(.large, by: 2))
    #expect(smaller < title)
    #expect(larger > title)
  }
}

@MainActor
struct TextSizeAndThemeRelayoutTests {
  private func post() -> Post {
    let post = Post(id: postSampleData.id)
    post.data = postSampleData
    return post
  }

  @Test func aLargerTextSizeSettingMeasuresTitlesTaller() throws {
    let saved = ContentTextScale.dynamicTypeSize
    defer { ContentTextScale.dynamicTypeSize = saved }
    ContentTextScale.dynamicTypeSize = .large
    let post = post()
    post.setupHelioData(contentWidth: 400, theme: defaultTheme, fetchAvatar: false)
    let before = try #require(post.helioData?.postDimensions.titleSize)

    ContentTextScale.dynamicTypeSize = ContentTextScale.adjusted(.large, by: 3)
    post.relayout(contentWidth: 400, theme: defaultTheme)
    let after = try #require(post.helioData?.postDimensions.titleSize)
    #expect(after.height > before.height)
  }

  @Test func aNewThemeDrawsTitlesInItsColor() throws {
    let saved = ContentTextScale.dynamicTypeSize
    defer { ContentTextScale.dynamicTypeSize = saved }
    ContentTextScale.dynamicTypeSize = .large
    let post = post()
    post.setupHelioData(contentWidth: 400, theme: defaultTheme, fetchAvatar: false)
    let before = try #require(post.helioData?.titleAttr)

    let highContrast = ThemePreset.highContrast.theme
    post.relayout(contentWidth: 400, theme: highContrast)
    let after = try #require(post.helioData?.titleAttr)
    #expect(after !== before)
    #expect(post.helioData?.layoutTitleText == highContrast.postLinks.theme.titleText)

    // The same theme again keeps it.
    post.relayout(contentWidth: 400, theme: highContrast)
    #expect(post.helioData?.titleAttr === after)
  }
}
