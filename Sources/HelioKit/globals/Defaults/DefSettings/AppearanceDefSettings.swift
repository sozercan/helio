//
//  AppearanceDefSettings.swift
//  Helio
//
//  Created by Igor Marcossi on 15/12/23.
//

import Defaults
import SwiftUI

enum AppColorScheme: String, Codable, CaseIterable, Defaults.Serializable {
  case system, light, dark

  var label: String {
    switch self {
    case .system: "System"
    case .light: "Light"
    case .dark: "Dark"
    }
  }

  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

struct AppearanceDefSettings: Equatable, Hashable, Codable, Defaults.Serializable {
  var replyModalBlurBackground: Bool = true
  var newPostModalBlurBackground: Bool = true
  var showUsernameInTabBar: Bool = false
  var disableAlphabetLettersSectionsInSubsList: Bool = false
  var themeStoreTint: Bool = true
  var colorScheme: AppColorScheme = .system
}
