import Defaults
import Foundation

func removeDefaultThemeFromThemes() {
  Defaults[.ThemesDefSettings].themesPresets = Defaults[.ThemesDefSettings].themesPresets.filter { $0.id != "default" }
}
