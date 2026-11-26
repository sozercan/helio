#if targetEnvironment(macCatalyst)
  import SwiftUI
  import UIKit

  final class MacTabToolbar: NSObject, NSToolbarDelegate {
    private static let tabsID = NSToolbarItem.Identifier("helio.tabs")
    private static let tabs: [Nav.TabIdentifier] = [.posts, .inbox, .me, .search, .settings]

    private var titles: [Nav.TabIdentifier: String] = [.posts: "Posts", .inbox: "Inbox", .me: "Me", .search: "Search", .settings: "Settings"]
    private var group: NSToolbarItemGroup?
    private weak var toolbar: NSToolbar?
    private var actions: [NSToolbarItem.Identifier: ScreenAction] = [:]
    private var shown: [ObjectIdentifier: ScreenAction] = [:]

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

    func setTitle(_ title: String, for tab: Nav.TabIdentifier) {
      guard titles[tab] != title else { return }
      titles[tab] = title
      if let index = Self.tabs.firstIndex(of: tab), let group, group.subitems.indices.contains(index) {
        group.subitems[index].title = title
        group.subitems[index].label = title
      }
    }

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

    private func observeActions() {
      withObservationTracking {
        _ = CommandTargets.shared.targets
        _ = Nav.shared.presentingSheet
      } onChange: { [weak self] in
        Task { @MainActor in
          self?.syncItems()
          self?.observeActions()
        }
      }
      syncItems()
    }

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
      var configured: [ObjectIdentifier: ScreenAction] = [:]
      for item in toolbar.items {
        guard let action = actions[item.itemIdentifier] else { continue }
        let key = ObjectIdentifier(item)
        if shown[key] != action {
          configure(item, for: action)
        }
        configured[key] = action
        item.autovalidates = false
        let enabled = !Self.screensCovered
        if item.isEnabled != enabled {
          item.isEnabled = enabled
        }
      }
      shown = configured
    }

    private static var screensCovered: Bool {
      CommandTargets.shared.showsModal || Nav.shared.presentingSheet != nil
    }

    private func configure(_ item: NSToolbarItem, for action: ScreenAction) {
      item.label = action.title
      item.toolTip = action.title
      item.image = UIImage(systemName: action.systemImage)
      item.isBordered = true
      item.visibilityPriority = .low
      switch action.content {
      case .button:
        item.target = self
        item.action = #selector(actionPicked(_:))
      case let .menu(entries):
        let id = item.itemIdentifier
        (item as? NSMenuToolbarItem)?.itemMenu = UIMenu(children: entries.enumerated().map { menuElement($1, path: [$0], in: id) })
      }
    }

    private func menuElement(_ entry: ScreenAction.Entry, path: [Int], in id: NSToolbarItem.Identifier) -> UIMenuElement {
      func children(_ entries: [ScreenAction.Entry]) -> [UIMenuElement] {
        entries.enumerated().map { menuElement($1, path: path + [$0], in: id) }
      }
      switch entry {
      case let .choice(title, systemImage, isOn, _):
        return UIAction(title: title, image: systemImage.flatMap { UIImage(systemName: $0) }, state: isOn ? .on : .off) { [weak self] _ in
          self?.choose(path, in: id)
        }
      case let .submenu(title, systemImage, entries):
        return UIMenu(title: title, image: systemImage.flatMap { UIImage(systemName: $0) }, children: children(entries))
      case let .section(title, entries):
        return UIMenu(title: title ?? "", options: .displayInline, children: children(entries))
      }
    }

    private func choose(_ path: [Int], in id: NSToolbarItem.Identifier) {
      guard case let .menu(entries)? = actions[id]?.content, let entry = ScreenAction.Entry.at(path, in: entries),
            case let .choice(_, _, _, select) = entry else { return }
      select()
    }

    @objc private func actionPicked(_ sender: NSToolbarItem) {
      guard !Self.screensCovered else { return }
      actions[sender.itemIdentifier]?.perform()
    }

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
      #if compiler(>=6.4)
        if #available(macCatalyst 27.0, *) {
          group.role = .tabs
        }
      #endif
      group.selectedIndex = Self.tabs.firstIndex(of: Nav.shared.activeTab) ?? 0
      group.visibilityPriority = .user
      if group.responds(to: NSSelectorFromString("setControlRepresentation:")) {
        group.setValue(1, forKey: "controlRepresentation")
      }
      self.group = group
      return group
    }
  }

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
