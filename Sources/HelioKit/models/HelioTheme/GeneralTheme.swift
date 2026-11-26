import Foundation

struct GeneralTheme: Codable, Hashable, Equatable {
  var navPanelBG: ThemeForegroundBG
  var tabBarBG: ThemeForegroundBG
  var floatingPanelsBG: ThemeForegroundBG
  var modalsBG: ThemeForegroundBG
  var accentColor: ColorSchemes<ThemeColor>
}
