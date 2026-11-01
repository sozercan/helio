//
//  NavCommands.swift
//  Helio
//

import SwiftUI

/// Menu bar items and keyboard shortcuts for moving between tabs on Mac and on iPad with a
/// hardware keyboard.
struct NavCommands: Commands {
  var body: some Commands {
    CommandGroup(replacing: .appSettings) {
      Button("Settings…") { Nav.shared.activeTab = .settings }
        .keyboardShortcut(",")
    }

    CommandMenu("Go") {
      Button("Posts") { Nav.shared.activeTab = .posts }
        .keyboardShortcut("1")
      Button("Inbox") { Nav.shared.activeTab = .inbox }
        .keyboardShortcut("2")
      Button("Me") { Nav.shared.activeTab = .me }
        .keyboardShortcut("3")
      Button("Search") { Nav.shared.activeTab = .search }
        .keyboardShortcut("4")

      Divider()

      Button("Back") { Nav.back() }
        .keyboardShortcut("[")
        .disabled(!Nav.shared.activeRouter.canGoBack)
    }
  }
}
