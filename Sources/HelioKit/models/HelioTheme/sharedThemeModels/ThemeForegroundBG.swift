import Foundation

struct ThemeForegroundBG: Codable, Hashable, Equatable {
  var blurry: Bool
  var color: ColorSchemes<ThemeColor>
}
