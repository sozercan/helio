//
//  defaultTheme.swift
//  Helio
//
//  Created by Igor Marcossi on 07/09/23.
//

import Foundation
import SwiftUI

let defaultAvatarTheme = AvatarTheme(size: 30, cornerRadius: 15, visible: true)

/// Apollo's palette, measured from Apollo 1.15 in light and dark mode.
private func scheme(_ light: String, _ dark: String) -> ColorSchemes<ThemeColor> {
  .init(light: .init(hex: light), dark: .init(hex: dark))
}

let themeFontPrimary = scheme("000000", "D0D1D6")
let themeFontSecondary = scheme("666666", "94969D")
// Lighter than Apollo's tertiary grey so small text meets 4.5:1 on the cell and flair backgrounds.
let themeFontTertiary = scheme("6E6F75", "8A8C93")
let themeCellBG = scheme("FFFFFF", "000000")
let themeBandColor = scheme("F2F3F7", "1A1A1A")
let themeAccentColor = scheme("007AFF", "2399FF")
/// Comment depth colors, Apollo's "Rainbow" theme.
let rainbowIndentColors: [ColorSchemes<ThemeColor>] = [
  scheme("F24336", "AF2E27"), scheme("FF922E", "B15610"), scheme("F9D141", "967727"), scheme("2D704C", "2D704C"),
  scheme("0D74DC", "1F68B1"), scheme("224688", "224688"), scheme("643B95", "643B95"),
]

let listSectionBGTheme: ColorSchemes<ThemeColor> = .init(light: .init(hex: "ffffff"), dark: .init(hex: "1C1C1E"))
let defaultBG = scheme("F2F3F7", "000000")
private let clearColor: ColorSchemes<ThemeColor> = .init(light: .init(hex: "ffffff", alpha: 0), dark: .init(hex: "ffffff", alpha: 0))
let defaultThemeDividerColor = scheme("CCCCCC", "323740")
let listDefaultBGImage: ColorSchemes<String> = .init(light: "helioNoBG", dark: "helioNoBG")
let defaultFancyDivider: LineTheme = .init(style: .fancy, thickness: 8, color: themeBandColor)
let defaultThemeBG: ThemeBG = .color(defaultBG)

let badgeTheme: BadgeTheme = .init(
  avatar: AvatarTheme(size: 32, cornerRadius: 16, visible: false),
  authorText: .init(size: 14, color: themeFontSecondary, weight: .medium),
  subColor: themeFontSecondary,
  flairText: .init(size: 12, color: themeFontTertiary),
  flairBackground: themeBandColor,
  statsText: .init(size: 13, color: themeFontSecondary), spacing: 8,
  forceSubsAsTags: false,
)

private let commentBadgeTheme: BadgeTheme = .init(
  avatar: AvatarTheme(size: 32, cornerRadius: 16, visible: false),
  authorText: .init(size: 14, color: themeFontPrimary, weight: .medium),
  subColor: themeAccentColor,
  flairText: .init(size: 12, color: themeFontTertiary),
  flairBackground: themeBandColor,
  statsText: .init(size: 14, color: themeFontTertiary), spacing: 8,
  forceSubsAsTags: false,
)

let defaultTheme = HelioTheme(
  metadata: .init(
    name: "Default",
    description: "The default Helio theme. Apollo's layout with iOS's Liquid Glass.",
    color: .init(hex: "007AFF"),
    icon: "paintbrush.fill",
    author: "Helio",
  ),
  id: "default",
  postLinks: .init(
    theme: .init(
      cornerRadius: 0,
      mediaCornerRadius: 10,
      innerPadding: .init(horizontal: 16, vertical: 14),
      outerHPadding: 0,
      stickyPostBorderColor: .init(thickness: 4, color: .init(light: .init(hex: "2FD058", alpha: 0.12), dark: .init(hex: "2FD058", alpha: 0.12))),
      titleText: .init(size: 17, color: themeFontPrimary),
      bodyText: .init(size: 15, color: themeFontSecondary),
      linespacing: 0,
      badge: badgeTheme,
      verticalElementsSpacing: 12,
      bg: .init(blurry: false, color: themeCellBG),
      unseenType: .fade,
      unseenFadeOpacity: 1,
      compactSelftextPostLinkPlaceholderImg: .init(type: .icon, color: .init(light: .init(hex: "000000", alpha: 0.2), dark: .init(hex: "ffffff", alpha: 0.2))),
      showDivider: false,
    ),
    spacing: 0,
    divider: defaultFancyDivider,
    bg: defaultThemeBG,
    stickyFilters: false,
    filterText: .init(size: 17, color: .init(light: .init(hex: "000000"), dark: .init(hex: "000000")), weight: .semibold),
    filterPadding: .init(horizontal: 6, vertical: 8),
    filterOpacity: 0.3,
  ),
  posts: .init(
    padding: .init(horizontal: 16, vertical: 12),
    spacing: 12,
    badge: badgeTheme,
    bg: .color(themeCellBG),
    commentsDistance: 0,
    titleText: .init(size: 19, color: themeFontPrimary, weight: .medium),
    bodyText: .init(size: 15, color: themeFontPrimary),
    linespacing: 0,
    inlineFloatingPill: false,
  ),
  comments: .init(
    theme: .init(
      innerPadding: .init(horizontal: 15, vertical: 10),
      outerHPadding: 0,
      repliesSpacing: 0,
      indentCurve: 12,
      indentColor: defaultThemeDividerColor,
      indentColors: rainbowIndentColors,
      cornerRadius: 0,
      badge: commentBadgeTheme,
      bodyText: .init(size: 15, color: themeFontPrimary),
      bodyAuthorSpacing: 6,
      linespacing: 0,
      bg: themeCellBG,
      loadMoreInnerPadding: .init(horizontal: 10, vertical: 6),
      loadMoreText: .init(size: 15, color: themeAccentColor, weight: .semibold),
      loadMoreBackground: themeBandColor,
      unseenDot: themeAccentColor,
    ),
    spacing: 0,
    divider: .init(style: .no, thickness: 1, color: defaultThemeDividerColor),
    //    bg: defaultThemeBG
  ),
  lists: .init(
    bg: defaultThemeBG,
    foreground: .init(blurry: false, color: listSectionBGTheme),
    dividersColors: defaultThemeDividerColor,
  ),
  general: .init(
    navPanelBG: .init(blurry: true, color: clearColor),
    tabBarBG: .init(blurry: true, color: clearColor),
    floatingPanelsBG: .init(blurry: true, color: clearColor),
    modalsBG: .init(blurry: true, color: clearColor),
    accentColor: themeAccentColor,
  ),
)
