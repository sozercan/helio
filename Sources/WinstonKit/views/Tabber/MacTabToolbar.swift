//
//  MacTabToolbar.swift
//  winston
//

#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

/// The Mac window's toolbar, with the tab switcher at its trailing edge.
///
/// While a split view shows its sidebar (the Posts tab), the window's toolbar starts after the
/// sidebar, so anything centered or leading in it, the tab bar and window title included, moved
/// sideways whenever the tab changed. The trailing edge is the same with or without a sidebar,
/// so the tabs sit there and the title is hidden. `Tabber` hides UIKit's own tab bar on Mac.
///
/// The Posts tab also gets the standard sidebar button, which leads the toolbar like in other
/// Mac apps, instead of SwiftUI's button inside the subs list.
final class MacTabToolbar: NSObject, NSToolbarDelegate {
  private static let tabsID = NSToolbarItem.Identifier("winston.tabs")
  private static let tabs: [(Nav.TabIdentifier, String)] = [
    (.posts, "Posts"), (.inbox, "Inbox"), (.me, "Me"), (.search, "Search"), (.settings, "Settings"),
  ]

  private var group: NSToolbarItemGroup?
  private weak var toolbar: NSToolbar?

  /// Gives the scene's window this toolbar, once.
  func install(in scene: UIWindowScene) {
    guard let titlebar = scene.titlebar, titlebar.toolbar?.delegate !== self else { return }
    let toolbar = NSToolbar(identifier: "winston.main")
    toolbar.delegate = self
    toolbar.displayMode = .iconOnly
    toolbar.allowsUserCustomization = false
    self.toolbar = toolbar
    titlebar.toolbar = toolbar
    titlebar.toolbarStyle = .unified
    titlebar.titleVisibility = .hidden
  }

  /// Shows `tab` as selected, for tab changes made elsewhere (menu commands, links), and the
  /// sidebar button only where there's a sidebar.
  func select(_ tab: Nav.TabIdentifier) {
    if let index = Self.tabs.firstIndex(where: { $0.0 == tab }), group?.selectedIndex != index {
      group?.selectedIndex = index
    }
    guard let toolbar else { return }
    let toggleIndex = toolbar.items.firstIndex { $0.itemIdentifier == .toggleSidebar }
    if tab == .posts, toggleIndex == nil {
      toolbar.insertItem(withItemIdentifier: .toggleSidebar, at: 0)
    } else if tab != .posts, let toggleIndex {
      toolbar.removeItem(at: toggleIndex)
    }
  }

  @objc private func tabPicked(_ sender: NSToolbarItemGroup) {
    guard Self.tabs.indices.contains(sender.selectedIndex) else { return }
    Nav.shared.activeTab = Self.tabs[sender.selectedIndex].0
  }

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    (Nav.shared.activeTab == .posts ? [.toggleSidebar] : []) + [.flexibleSpace, Self.tabsID]
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [.toggleSidebar, .flexibleSpace, Self.tabsID]
  }

  func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
    guard itemIdentifier == Self.tabsID else { return nil }
    let group = NSToolbarItemGroup(
      itemIdentifier: itemIdentifier,
      titles: Self.tabs.map(\.1),
      selectionMode: .selectOne,
      labels: nil,
      target: self,
      action: #selector(tabPicked(_:))
    )
    if #available(macCatalyst 27.0, *) {
      group.role = .tabs
    }
    group.selectedIndex = Self.tabs.firstIndex { $0.0 == Nav.shared.activeTab } ?? 0
    self.group = group
    return group
  }
}

/// Installs a `MacTabToolbar` on the window this view is in.
struct MacTabToolbarInstaller: UIViewRepresentable {
  let toolbar: MacTabToolbar

  func makeUIView(context: Context) -> InstallerView {
    let view = InstallerView()
    view.toolbar = toolbar
    return view
  }

  func updateUIView(_ uiView: InstallerView, context: Context) {}

  final class InstallerView: UIView {
    var toolbar: MacTabToolbar?

    override func didMoveToWindow() {
      super.didMoveToWindow()
      if let scene = window?.windowScene { toolbar?.install(in: scene) }
    }
  }
}

#endif
