//
//  PostLinkTheme.swift
//  Helio
//
//  Created by Igor Marcossi on 07/09/23.
//

import Foundation

struct PostLinkTheme: Codable, Hashable, Equatable {
  enum CodingKeys: String, CodingKey {
    case cornerRadius, mediaCornerRadius, innerPadding, outerHPadding, stickyPostBorderColor, titleText, bodyText, linespacing, badge, verticalElementsSpacing, bg, unseenType, unseenFadeOpacity, compactSelftextPostLinkPlaceholderImg, showDivider, titleFlair
  }

  var cornerRadius: CGFloat
  var mediaCornerRadius: CGFloat
  var innerPadding: ThemePadding
  var outerHPadding: CGFloat
  var stickyPostBorderColor: LineTheme
  var titleText: ThemeText
  var bodyText: ThemeText
  var linespacing: CGFloat
  var badge: BadgeTheme
  var verticalElementsSpacing: CGFloat
  var bg: ThemeForegroundBG
  var unseenType: UnseenType
  var unseenFadeOpacity: CGFloat
  var compactSelftextPostLinkPlaceholderImg: CompactSelftextPostLinkPlaceholderImg
  var showDivider: Bool
  /// Uncolored flair in titles. It's drawn into the title once, so it looks the same in light
  /// and dark mode; `nil` keeps a translucent grey that reads as a grey pill on either.
  var titleFlair: TitleFlair?

  /// What titles are drawn with (`createTitleTagsAttrString`): a new style draws them again.
  var titleStyle: TitleStyle {
    .init(text: titleText, flair: titleFlair)
  }

  init(cornerRadius: CGFloat, mediaCornerRadius: CGFloat, innerPadding: ThemePadding, outerHPadding: CGFloat, stickyPostBorderColor: LineTheme, titleText: ThemeText, bodyText: ThemeText, linespacing: CGFloat, badge: BadgeTheme, verticalElementsSpacing: CGFloat, bg: ThemeForegroundBG, unseenType: UnseenType, unseenFadeOpacity: CGFloat, compactSelftextPostLinkPlaceholderImg: CompactSelftextPostLinkPlaceholderImg, showDivider: Bool, titleFlair: TitleFlair? = nil) {
    self.cornerRadius = cornerRadius
    self.mediaCornerRadius = mediaCornerRadius
    self.innerPadding = innerPadding
    self.outerHPadding = outerHPadding
    self.stickyPostBorderColor = stickyPostBorderColor
    self.titleText = titleText
    self.bodyText = bodyText
    self.linespacing = linespacing
    self.badge = badge
    self.verticalElementsSpacing = verticalElementsSpacing
    self.bg = bg
    self.unseenType = unseenType
    self.unseenFadeOpacity = unseenFadeOpacity
    self.compactSelftextPostLinkPlaceholderImg = compactSelftextPostLinkPlaceholderImg
    self.showDivider = showDivider
    self.titleFlair = titleFlair
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(cornerRadius, forKey: .cornerRadius)
    try container.encodeIfPresent(mediaCornerRadius, forKey: .mediaCornerRadius)
    try container.encodeIfPresent(innerPadding, forKey: .innerPadding)
    try container.encodeIfPresent(outerHPadding, forKey: .outerHPadding)
    try container.encodeIfPresent(stickyPostBorderColor, forKey: .stickyPostBorderColor)
    try container.encodeIfPresent(titleText, forKey: .titleText)
    try container.encodeIfPresent(bodyText, forKey: .bodyText)
    try container.encodeIfPresent(linespacing, forKey: .linespacing)
    try container.encodeIfPresent(badge, forKey: .badge)
    try container.encodeIfPresent(verticalElementsSpacing, forKey: .verticalElementsSpacing)
    try container.encodeIfPresent(bg, forKey: .bg)
    try container.encodeIfPresent(unseenType, forKey: .unseenType)
    try container.encodeIfPresent(unseenFadeOpacity, forKey: .unseenFadeOpacity)
    try container.encodeIfPresent(compactSelftextPostLinkPlaceholderImg, forKey: .compactSelftextPostLinkPlaceholderImg)
    try container.encodeIfPresent(showDivider, forKey: .showDivider)
    try container.encodeIfPresent(titleFlair, forKey: .titleFlair)
  }

  init(from decoder: Decoder) throws {
    let t = defaultTheme.postLinks.theme
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.cornerRadius = try container.decodeIfPresent(CGFloat.self, forKey: .cornerRadius) ?? t.cornerRadius
    self.mediaCornerRadius = try container.decodeIfPresent(CGFloat.self, forKey: .mediaCornerRadius) ?? t.mediaCornerRadius
    self.innerPadding = try container.decodeIfPresent(ThemePadding.self, forKey: .innerPadding) ?? t.innerPadding
    self.outerHPadding = try container.decodeIfPresent(CGFloat.self, forKey: .outerHPadding) ?? t.outerHPadding
    self.stickyPostBorderColor = try container.decodeIfPresent(LineTheme.self, forKey: .stickyPostBorderColor) ?? t.stickyPostBorderColor
    self.titleText = try container.decodeIfPresent(ThemeText.self, forKey: .titleText) ?? t.titleText
    self.bodyText = try container.decodeIfPresent(ThemeText.self, forKey: .bodyText) ?? t.bodyText
    self.linespacing = try container.decodeIfPresent(CGFloat.self, forKey: .linespacing) ?? t.linespacing
    self.badge = try container.decodeIfPresent(BadgeTheme.self, forKey: .badge) ?? t.badge
    self.verticalElementsSpacing = try container.decodeIfPresent(CGFloat.self, forKey: .verticalElementsSpacing) ?? t.verticalElementsSpacing
    self.bg = try container.decodeIfPresent(ThemeForegroundBG.self, forKey: .bg) ?? t.bg
    self.unseenType = try container.decodeIfPresent(UnseenType.self, forKey: .unseenType) ?? t.unseenType
    self.unseenFadeOpacity = try container.decodeIfPresent(CGFloat.self, forKey: .unseenFadeOpacity) ?? t.unseenFadeOpacity
    self.compactSelftextPostLinkPlaceholderImg = try container.decodeIfPresent(CompactSelftextPostLinkPlaceholderImg.self, forKey: .compactSelftextPostLinkPlaceholderImg) ?? t.compactSelftextPostLinkPlaceholderImg
    self.showDivider = try container.decodeIfPresent(Bool.self, forKey: .showDivider) ?? t.showDivider
    // Optional: themes saved without it keep the translucent grey.
    self.titleFlair = try container.decodeIfPresent(TitleFlair.self, forKey: .titleFlair)
  }

  struct TitleFlair: Codable, Hashable, Equatable {
    var text: ThemeColor
    var background: ThemeColor
  }

  struct TitleStyle: Hashable {
    let text: ThemeText
    let flair: TitleFlair?
  }

  struct CompactSelftextPostLinkPlaceholderImg: Codable, Hashable, Equatable {
    var type: ImgType
    var color: ColorSchemes<ThemeColor>
    enum ImgType: String, Codable, Hashable, Equatable {
      case helio, icon
    }
  }
}
