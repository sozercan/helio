import Foundation
import SwiftUI

let defaultAvatarTheme = AvatarTheme(size: 30, cornerRadius: 15, visible: true)

private func scheme(_ light: String, _ dark: String) -> ColorSchemes<ThemeColor> {
  .init(light: .init(hex: light), dark: .init(hex: dark))
}

let themeFontPrimary = scheme("000000", "D0D1D6")
let themeFontSecondary = scheme("666666", "94969D")
let themeFontTertiary = scheme("6E6F75", "8A8C93")
let themeCellBG = scheme("FFFFFF", "000000")
let themeBandColor = scheme("F2F3F7", "1A1A1A")
let themeAccentColor = scheme("007AFF", "2399FF")
let themeQuoteText = scheme("6B6E78", "9294A0")
let rainbowIndentColors: [ColorSchemes<ThemeColor>] = [
  scheme("F24336", "AF2E27"), scheme("FF922E", "B15610"), scheme("F9D141", "967727"), scheme("2D704C", "2D704C"),
  scheme("0D74DC", "1F68B1"), scheme("224688", "224688"), scheme("643B95", "643B95"),
]
let highContrastIndentColors: [ColorSchemes<ThemeColor>] = [
  scheme("D70015", "FF6961"), scheme("C93400", "FFB340"), scheme("A05A00", "FFD426"), scheme("248A3D", "30DB5B"),
  scheme("0040DD", "409CFF"), scheme("3634A3", "7D7AFF"), scheme("8944AB", "DA8FFF"),
]

let highContrastPalette: [ColorSchemes<ThemeColor>: ColorSchemes<ThemeColor>] = [
  themeFontSecondary: scheme("4D4D4D", "B4B6BC"),
  themeFontTertiary: scheme("505156", "ADAFB5"),
  defaultThemeDividerColor: scheme("8E8E93", "6A6F7A"),
]

extension Color {
  static let secondaryText = themeFontSecondary.color()
}

let listSectionBGTheme: ColorSchemes<ThemeColor> = .init(light: .init(hex: "ffffff"), dark: .init(hex: "1C1C1E"))
let defaultBG = scheme("F2F3F7", "000000")
private let clearColor: ColorSchemes<ThemeColor> = .init(light: .init(hex: "ffffff", alpha: 0), dark: .init(hex: "ffffff", alpha: 0))
let defaultThemeDividerColor = scheme("CCCCCC", "323740")
let listDefaultBGImage: ColorSchemes<String> = .init(light: "helioNoBG", dark: "helioNoBG")
let defaultFancyDivider: LineTheme = .init(style: .fancy, thickness: 8, color: themeBandColor)
let defaultThemeBG: ThemeBG = .color(defaultBG)

let badgeTheme: BadgeTheme = ThemePalette.apollo.feedBadge

struct ThemePalette {
  var fontPrimary: ColorSchemes<ThemeColor>
  var fontSecondary: ColorSchemes<ThemeColor>
  var fontTertiary: ColorSchemes<ThemeColor>
  var cellBG: ColorSchemes<ThemeColor>
  var band: ColorSchemes<ThemeColor>
  var flairBackground: ColorSchemes<ThemeColor>
  var accent: ColorSchemes<ThemeColor>
  var quoteText: ColorSchemes<ThemeColor>
  var accentText: ColorSchemes<ThemeColor>?
  var upvoteText: ColorSchemes<ThemeColor>?
  var downvoteText: ColorSchemes<ThemeColor>?
  var scoreText: ColorSchemes<ThemeColor>?
  var divider: ColorSchemes<ThemeColor>
  var background: ColorSchemes<ThemeColor>
  var listRow: ColorSchemes<ThemeColor>
  var feedDivider: LineTheme
  var depthColors: [ColorSchemes<ThemeColor>]
  var titleFlair: PostLinkTheme.TitleFlair?

  static let apollo = ThemePalette(
    fontPrimary: themeFontPrimary,
    fontSecondary: themeFontSecondary,
    fontTertiary: themeFontTertiary,
    cellBG: themeCellBG,
    band: themeBandColor,
    flairBackground: themeBandColor,
    accent: themeAccentColor,
    quoteText: themeQuoteText,
    divider: defaultThemeDividerColor,
    background: defaultBG,
    listRow: listSectionBGTheme,
    feedDivider: defaultFancyDivider,
    depthColors: rainbowIndentColors,
  )

  static let trueBlack: ThemePalette = {
    var palette = ThemePalette.apollo
    palette.band = .init(light: themeBandColor.light, dark: .init(hex: "000000"))
    palette.listRow = .init(light: listSectionBGTheme.light, dark: .init(hex: "000000"))
    palette.divider = scheme("CCCCCC", "2C2C2E")
    palette.feedDivider = .init(style: .fancy, thickness: 8, color: palette.band)
    return palette
  }()

  static let highContrast: ThemePalette = {
    var palette = ThemePalette.apollo
    palette.fontPrimary = scheme("000000", "FFFFFF")
    palette.fontSecondary = highContrastPalette[themeFontSecondary] ?? themeFontSecondary
    palette.fontTertiary = highContrastPalette[themeFontTertiary] ?? themeFontTertiary
    palette.divider = highContrastPalette[defaultThemeDividerColor] ?? defaultThemeDividerColor
    palette.quoteText = palette.fontSecondary
    palette.accent = scheme("003CD0", "62ADFF")
    palette.accentText = palette.accent
    palette.upvoteText = scheme("8A2E00", "FFA066")
    palette.downvoteText = scheme("2E35A8", "ABAEFF")
    palette.scoreText = palette.fontSecondary
    palette.feedDivider = .init(style: .line, thickness: 1, color: palette.divider)
    palette.depthColors = highContrastIndentColors
    palette.titleFlair = .init(text: .init(hex: "FFFFFF"), background: .init(hex: "505156"), nsfwBackground: .init(hex: "A50E0E"))
    return palette
  }()

  var feedBadge: BadgeTheme {
    .init(
      avatar: AvatarTheme(size: 32, cornerRadius: 16, visible: false),
      authorText: .init(size: 14, color: fontSecondary, weight: .medium),
      subColor: fontSecondary,
      flairText: .init(size: 12, color: fontTertiary),
      flairBackground: flairBackground,
      statsText: .init(size: 13, color: fontSecondary), spacing: 8,
      forceSubsAsTags: false,
      upvoteText: upvoteText,
      downvoteText: downvoteText,
      newCommentsText: accentText,
      scoreText: scoreText,
    )
  }

  var commentBadge: BadgeTheme {
    .init(
      avatar: AvatarTheme(size: 32, cornerRadius: 16, visible: false),
      authorText: .init(size: 14, color: fontPrimary, weight: .medium),
      subColor: accent,
      flairText: .init(size: 12, color: fontTertiary),
      flairBackground: flairBackground,
      statsText: .init(size: 14, color: fontTertiary), spacing: 8,
      forceSubsAsTags: false,
      upvoteText: upvoteText,
      downvoteText: downvoteText,
      newCommentsText: accentText,
      scoreText: scoreText,
    )
  }
}

let defaultTheme = HelioTheme(
  palette: .apollo,
  id: "default",
  metadata: .init(
    name: "Apollo",
    description: "Apollo's look, in light and dark.",
    color: .init(hex: "007AFF"),
    icon: "paintbrush.fill",
    author: "Helio",
  ),
)

extension HelioTheme {
  init(palette: ThemePalette, id: String, metadata: HelioThemeMeta) {
    self.init(
      metadata: metadata,
      id: id,
      postLinks: .init(
        theme: .init(
          cornerRadius: 0,
          mediaCornerRadius: 10,
          innerPadding: .init(horizontal: 16, vertical: 14),
          outerHPadding: 0,
          stickyPostBorderColor: .init(thickness: 4, color: .init(light: .init(hex: "2FD058", alpha: 0.12), dark: .init(hex: "2FD058", alpha: 0.12))),
          titleText: .init(size: 17, color: palette.fontPrimary),
          bodyText: .init(size: 15, color: palette.fontSecondary),
          linespacing: 0,
          badge: palette.feedBadge,
          verticalElementsSpacing: 12,
          bg: .init(blurry: false, color: palette.cellBG),
          unseenType: .fade,
          unseenFadeOpacity: 1,
          compactSelftextPostLinkPlaceholderImg: .init(type: .icon, color: .init(light: .init(hex: "000000", alpha: 0.2), dark: .init(hex: "ffffff", alpha: 0.2))),
          showDivider: false,
          titleFlair: palette.titleFlair,
        ),
        spacing: 0,
        divider: palette.feedDivider,
        bg: .color(palette.background),
        stickyFilters: false,
        filterText: .init(size: 17, color: .init(light: .init(hex: "000000"), dark: .init(hex: "000000")), weight: .semibold),
        filterPadding: .init(horizontal: 6, vertical: 8),
        filterOpacity: 0.3,
      ),
      posts: .init(
        padding: .init(horizontal: 16, vertical: 12),
        spacing: 12,
        badge: palette.feedBadge,
        bg: .color(palette.cellBG),
        commentsDistance: 0,
        titleText: .init(size: 19, color: palette.fontPrimary, weight: .medium),
        bodyText: .init(size: 15, color: palette.fontPrimary),
        quoteText: palette.quoteText,
        linkText: palette.accentText,
        linespacing: 0,
        inlineFloatingPill: false,
      ),
      comments: .init(
        theme: .init(
          innerPadding: .init(horizontal: 15, vertical: 10),
          outerHPadding: 0,
          repliesSpacing: 0,
          indentCurve: 12,
          indentColor: palette.divider,
          indentColors: palette.depthColors,
          cornerRadius: 0,
          badge: palette.commentBadge,
          bodyText: .init(size: 15, color: palette.fontPrimary),
          quoteText: palette.quoteText,
          linkText: palette.accentText,
          bodyAuthorSpacing: 6,
          linespacing: 0,
          bg: palette.cellBG,
          loadMoreInnerPadding: .init(horizontal: 10, vertical: 6),
          loadMoreText: .init(size: 15, color: palette.accent, weight: .semibold),
          loadMoreBackground: palette.flairBackground,
          unseenDot: palette.accent,
        ),
        spacing: 0,
        divider: .init(style: .no, thickness: 1, color: palette.divider),
      ),
      lists: .init(
        bg: .color(palette.background),
        foreground: .init(blurry: false, color: palette.listRow),
        dividersColors: palette.divider,
      ),
      general: .init(
        navPanelBG: .init(blurry: true, color: clearColor),
        tabBarBG: .init(blurry: true, color: clearColor),
        floatingPanelsBG: .init(blurry: true, color: clearColor),
        modalsBG: .init(blurry: true, color: clearColor),
        accentColor: themeAccentColor,
      ),
    )
  }
}

struct ThemePreset: Identifiable {
  enum Modes {
    case lightAndDark, dark

    var label: String {
      switch self {
      case .lightAndDark: "Light & Dark"
      case .dark: "Dark"
      }
    }
  }

  let theme: HelioTheme
  let modes: Modes

  var id: String {
    theme.id
  }

  static let apollo = ThemePreset(theme: defaultTheme, modes: .lightAndDark)

  static let trueBlack = ThemePreset(theme: HelioTheme(palette: .trueBlack, id: "trueBlack", metadata: .init(
    name: "True Black",
    description: "Pure black backgrounds in dark mode, for OLED screens.",
    color: .init(hex: "000000"),
    icon: "moon.fill",
    author: "Helio",
  )), modes: .dark)

  static let highContrast = ThemePreset(theme: HelioTheme(palette: .highContrast, id: "highContrast", metadata: .init(
    name: "High Contrast",
    description: "Stronger text and separators, always on.",
    color: .init(hex: "003CD0"),
    icon: "circle.lefthalf.filled",
    author: "Helio",
  )), modes: .lightAndDark)

  static let all: [ThemePreset] = [.apollo, .trueBlack, .highContrast]
}

extension HelioTheme {
  static func selected(in settings: ThemesDefSettings) -> HelioTheme {
    ThemePreset.all.first { $0.id == settings.selectedThemeID }?.theme
      ?? settings.themesPresets.first { $0.id == settings.selectedThemeID }
      ?? defaultTheme
  }
}
