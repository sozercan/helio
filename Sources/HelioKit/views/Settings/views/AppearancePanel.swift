//
//  AppearancePanel.swift
//  Helio
//
//  Created by Igor Marcossi on 05/07/23.
//

import Defaults
import SwiftUI

struct AppearancePanel: View {
  @Default(.AppearanceDefSettings) var appearanceDefSettings

  @Environment(\.useTheme) private var theme

  var body: some View {
    List {
      Section("Theme") {
        Picker("Appearance", selection: $appearanceDefSettings.colorScheme) {
          ForEach(AppColorScheme.allCases, id: \.self) { scheme in
            Text(scheme.label).tag(scheme)
          }
        }
        .pickerStyle(.inline)
        .labelsHidden()
      }
    }
    .themedListBG(theme.lists.bg)
    .navigationTitle("Appearance")
    .navigationBarTitleDisplayMode(.inline)
  }
}
