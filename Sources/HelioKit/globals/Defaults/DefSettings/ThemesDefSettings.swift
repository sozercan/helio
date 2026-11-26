import Defaults

struct ThemesDefSettings: Equatable, Hashable, Codable, Defaults.Serializable {
  var themesPresets: [HelioTheme] = []
  var selectedThemeID: String = "default"
}
