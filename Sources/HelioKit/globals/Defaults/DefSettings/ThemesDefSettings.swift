//
//  ThemesDefSettings.swift
//  Helio
//
//  Created by Igor Marcossi on 15/12/23.
//

import Defaults

struct ThemesDefSettings: Equatable, Hashable, Codable, Defaults.Serializable {
  var themesPresets: [HelioTheme] = []
  var selectedThemeID: String = "default"
}
