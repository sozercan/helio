//
//  MacTabToolbar.swift
//  Helio
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
  ///
  /// The screens' own actions (sort, filters, a subreddit's info, the account switcher) are here
  /// too rather than in a navigation bar under the toolbar: each screen registers them with
  /// `CommandTargets`, and in the posts tab they sit above the column of the screen they belong
  /// to, after the split view's tracking separators.
  final class MacTabToolbar: NSObject, NSToolbarDelegate {
    private static let tabsID = NSToolbarItem.Identifier("helio.tabs")
    private static let tabs: [Nav.TabIdentifier] = [.posts, .inbox, .me, .search, .settings]

    private var titles: [Nav.TabIdentifier: String] = [.posts: "Posts", .inbox: "Inbox", .me: "Me", .search: "Search", .settings: "Settings"]
    private var group: NSToolbarItemGroup?
    private weak var toolbar: NSToolbar?
    /// The screen actions the toolbar shows, by item.
    private var actions: [NSToolbarItem.Identifier: ScreenAction] = [:]

    /// Gives the scene's window this toolbar, once.
    func install(in scene: UIWindowScene) {
      guard let titlebar = scene.titlebar, titlebar.toolbar?.delegate !== self else { return }
      let toolbar = NSToolbar(identifier: "helio.main")
      toolbar.delegate = self
      toolbar.displayMode = .iconOnly
      toolbar.allowsUserCustomization = false
      self.toolbar = toolbar
      titlebar.toolbar = toolbar
      titlebar.toolbarStyle = .unified
      titlebar.titleVisibility = .hidden
      observeActions()
    }

    /// Shows the tab's title, which for Me can be the username.
    func setTitle(_ title: String, for tab: Nav.TabIdentifier) {
      guard titles[tab] != title else { return }
      titles[tab] = title
      if let index = Self.tabs.firstIndex(of: tab), let group, group.subitems.indices.contains(index) {
        group.subitems[index].title = title
        group.subitems[index].label = title
      }
    }

    /// Shows `tab` as selected, for tab changes made elsewhere (menu commands, links), and the
    /// sidebar button only where there's a sidebar.
    func select(_ tab: Nav.TabIdentifier) {
      if let index = Self.tabs.firstIndex(of: tab), group?.selectedIndex != index {
        group?.selectedIndex = index
      }
      syncItems()
    }

    @objc private func tabPicked(_ sender: NSToolbarItemGroup) {
      guard Self.tabs.indices.contains(sender.selectedIndex) else { return }
      Nav.shared.activeTab = Self.tabs[sender.selectedIndex]
    }

    // MARK: Screen actions

    /// Keeps the actions current as screens come and go and their state changes.
    private func observeActions() {
      withObservationTracking {
        _ = CommandTargets.shared.targets
      } onChange: { [weak self] in
        Task { @MainActor in
          self?.syncItems()
          self?.observeActions()
        }
      }
      syncItems()
    }

    /// The items for the active tab and the screens it shows: in the posts tab, the sidebar
    /// button, then each column's actions at its trailing edge.
    private func itemIdentifiers() -> [NSToolbarItem.Identifier] {
      actions = [:]
      func items(_ column: Router.Column?) -> [NSToolbarItem.Identifier] {
        CommandTargets.shared.actions(in: column, postsTab: Nav.shared.activeTab == .posts).map { action in
          let id = NSToolbarItem.Identifier("helio.\(column.map { "\($0)" } ?? "screen").\(action.id.rawValue)")
          actions[id] = action
          return id
        }
      }
      guard Nav.shared.activeTab == .posts else {
        return items(nil) + [.flexibleSpace, Self.tabsID]
      }
      let post = items(.post)
      return [.toggleSidebar, .primarySidebarTrackingSeparatorItemIdentifier, .flexibleSpace] + items(.feed)
        + [.supplementarySidebarTrackingSeparatorItemIdentifier, .flexibleSpace] + post
        + (post.isEmpty ? [] : [.space]) + [Self.tabsID]
    }

    /// Brings the toolbar's items in line with `itemIdentifiers()`, leaving the ones that stay.
    private func syncItems() {
      guard let toolbar else { return }
      let desired = itemIdentifiers()
      if let edit = toolbarEdit(from: toolbar.items.map(\.itemIdentifier), to: desired) {
        for index in edit.range.reversed() {
          toolbar.removeItem(at: index)
        }
        for (offset, id) in edit.insert.enumerated() {
          toolbar.insertItem(withItemIdentifier: id, at: edit.range.lowerBound + offset)
        }
      }
      for item in toolbar.items {
        if let action = actions[item.itemIdentifier] {
          configure(item, for: action)
        }
      }
    }

    private func configure(_ item: NSToolbarItem, for action: ScreenAction) {
      item.label = action.title
      item.toolTip = action.title
      item.image = UIImage(systemName: action.systemImage)
      item.isBordered = true
      // In a narrow window the actions go to the overflow menu before the tabs give way.
      item.visibilityPriority = .low
      switch action.content {
      case .button:
        item.target = self
        item.action = #selector(actionPicked(_:))
      case let .menu(entries):
        (item as? NSMenuToolbarItem)?.itemMenu = UIMenu(children: entries.map(Self.menuElement))
      }
    }

    private static func menuElement(_ entry: ScreenAction.Entry) -> UIMenuElement {
      switch entry {
      case let .choice(title, systemImage, isOn, select):
        UIAction(title: title, image: systemImage.flatMap { UIImage(systemName: $0) }, state: isOn ? .on : .off) { _ in select() }
      case let .submenu(title, systemImage, entries):
        UIMenu(title: title, image: systemImage.flatMap { UIImage(systemName: $0) }, children: entries.map(menuElement))
      case let .section(title, entries):
        UIMenu(title: title ?? "", options: .displayInline, children: entries.map(menuElement))
      }
    }

    @objc private func actionPicked(_ sender: NSToolbarItem) {
      actions[sender.itemIdentifier]?.perform()
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      itemIdentifiers()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
      [.toggleSidebar, .primarySidebarTrackingSeparatorItemIdentifier, .supplementarySidebarTrackingSeparatorItemIdentifier, .flexibleSpace, .space, Self.tabsID] + Array(actions.keys)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
      if let action = actions[itemIdentifier] {
        let item = if case .menu = action.content {
          NSMenuToolbarItem(itemIdentifier: itemIdentifier)
        } else {
          NSToolbarItem(itemIdentifier: itemIdentifier)
        }
        configure(item, for: action)
        return item
      }
      guard itemIdentifier == Self.tabsID else { return nil }
      let group = NSToolbarItemGroup(
        itemIdentifier: itemIdentifier,
        titles: Self.tabs.map { titles[$0] ?? "" },
        selectionMode: .selectOne,
        labels: nil,
        target: self,
        action: #selector(tabPicked(_:)),
      )
      // `role` is in the 27 SDK (Swift 6.4); older Xcodes, like CI's, can't see it at all.
      #if compiler(>=6.4)
        if #available(macCatalyst 27.0, *) {
          group.role = .tabs
        }
      #endif
      group.selectedIndex = Self.tabs.firstIndex(of: Nav.shared.activeTab) ?? 0
      // Short of room, the tabs stay tabs and the screen actions go to the overflow menu,
      // rather than the tabs turning into a pop-up button. `controlRepresentation` is AppKit's,
      // not in Catalyst's headers, but the group answers to it.
      group.visibilityPriority = .user
      if group.responds(to: NSSelectorFromString("setControlRepresentation:")) {
        group.setValue(1, forKey: "controlRepresentation") // NSToolbarItemGroup.ControlRepresentation.expanded
      }
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
        if let scene = window?.windowScene {
          toolbar?.install(in: scene)
        }
      }
    }
  }

#endif
