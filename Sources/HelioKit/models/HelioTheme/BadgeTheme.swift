import Foundation
import SwiftUI

struct BadgeTheme: Codable, Hashable, Equatable {
  enum CodingKeys: String, CodingKey {
    case avatar, authorText, subColor, flairText, flairBackground, statsText, spacing, forceSubsAsTags, upvoteText, downvoteText, newCommentsText, scoreText
  }

  var avatar: AvatarTheme
  @Boxed var authorText: ThemeText
  @Boxed var subColor: ColorSchemes<ThemeColor>
  @Boxed var flairText: ThemeText
  @Boxed var flairBackground: ColorSchemes<ThemeColor>
  @Boxed var statsText: ThemeText
  var spacing: CGFloat
  var forceSubsAsTags: Bool
  @Boxed var upvoteText: ColorSchemes<ThemeColor>?
  @Boxed var downvoteText: ColorSchemes<ThemeColor>?
  @Boxed var newCommentsText: ColorSchemes<ThemeColor>?
  @Boxed var scoreText: ColorSchemes<ThemeColor>?

  var neutralScoreColor: Color {
    scoreText?.color() ?? .gray
  }

  func voteColor(_ likes: Bool?, neutral: Color) -> Color {
    switch likes {
    case true: upvoteText?.color() ?? .upvoteText
    case false: downvoteText?.color() ?? .downvoteText
    default: neutral
    }
  }

  init(avatar: AvatarTheme, authorText: ThemeText, subColor: ColorSchemes<ThemeColor>, flairText: ThemeText, flairBackground: ColorSchemes<ThemeColor>, statsText: ThemeText, spacing: CGFloat, forceSubsAsTags: Bool, upvoteText: ColorSchemes<ThemeColor>? = nil, downvoteText: ColorSchemes<ThemeColor>? = nil, newCommentsText: ColorSchemes<ThemeColor>? = nil, scoreText: ColorSchemes<ThemeColor>? = nil) {
    self.avatar = avatar
    self.authorText = authorText
    self.subColor = subColor
    self.flairText = flairText
    self.flairBackground = flairBackground
    self.statsText = statsText
    self.spacing = spacing
    self.forceSubsAsTags = forceSubsAsTags
    self.upvoteText = upvoteText
    self.downvoteText = downvoteText
    self.newCommentsText = newCommentsText
    self.scoreText = scoreText
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(avatar, forKey: .avatar)
    try container.encodeIfPresent(authorText, forKey: .authorText)
    try container.encodeIfPresent(subColor, forKey: .subColor)
    try container.encodeIfPresent(flairText, forKey: .flairText)
    try container.encodeIfPresent(flairBackground, forKey: .flairBackground)
    try container.encodeIfPresent(statsText, forKey: .statsText)
    try container.encodeIfPresent(spacing, forKey: .spacing)
    try container.encodeIfPresent(forceSubsAsTags, forKey: .forceSubsAsTags)
    try container.encodeIfPresent(upvoteText, forKey: .upvoteText)
    try container.encodeIfPresent(downvoteText, forKey: .downvoteText)
    try container.encodeIfPresent(newCommentsText, forKey: .newCommentsText)
    try container.encodeIfPresent(scoreText, forKey: .scoreText)
  }

  init(from decoder: Decoder) throws {
    let t = badgeTheme
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.avatar = try container.decodeIfPresent(AvatarTheme.self, forKey: .avatar) ?? t.avatar
    self.authorText = try container.decodeIfPresent(ThemeText.self, forKey: .authorText) ?? t.authorText
    self.subColor = try container.decodeIfPresent(ColorSchemes<ThemeColor>.self, forKey: .subColor) ?? t.subColor
    self.flairText = try container.decodeIfPresent(ThemeText.self, forKey: .flairText) ?? t.flairText
    self.flairBackground = try container.decodeIfPresent(ColorSchemes<ThemeColor>.self, forKey: .flairBackground) ?? t.flairBackground
    self.statsText = try container.decodeIfPresent(ThemeText.self, forKey: .statsText) ?? t.statsText
    self.spacing = try container.decodeIfPresent(CGFloat.self, forKey: .spacing) ?? t.spacing
    self.forceSubsAsTags = try container.decodeIfPresent(Bool.self, forKey: .forceSubsAsTags) ?? t.forceSubsAsTags
    self.upvoteText = try container.decodeIfPresent(ColorSchemes<ThemeColor>.self, forKey: .upvoteText)
    self.downvoteText = try container.decodeIfPresent(ColorSchemes<ThemeColor>.self, forKey: .downvoteText)
    self.newCommentsText = try container.decodeIfPresent(ColorSchemes<ThemeColor>.self, forKey: .newCommentsText)
    self.scoreText = try container.decodeIfPresent(ColorSchemes<ThemeColor>.self, forKey: .scoreText)
  }
}
