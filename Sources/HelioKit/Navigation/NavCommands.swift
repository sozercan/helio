//
//  NavCommands.swift
//  Helio
//

import Defaults
import SwiftUI

/// Menu bar items and keyboard shortcuts on Mac and on iPad with a hardware keyboard: the tabs,
/// Back, Refresh and Find, and the open post's. Shortcuts all take Command, so none of them
/// takes a key from a text field; the arrows also take Option, which text fields don't use.
struct NavCommands: Commands {
  private let targets = CommandTargets.shared
  /// Observed so the Accounts menu's check mark follows the selected account, which can change
  /// while nothing else in the menu bar does.
  @Default(.GeneralDefSettings) private var generalDefSettings

  /// A screen action's menu. While no screen shown has the action, `placeholder`'s items show
  /// disabled: always a submenu, as switching between a submenu and an item reorders the
  /// menu's items on Mac, and a submenu can't be disabled there.
  /// The shown screen's action with `id`, unless a reply, a full-screen viewer or a sheet covers
  /// it: acting on the screen behind could navigate under it or close it.
  private func screenAction(_ id: ScreenAction.ID) -> ScreenAction? {
    // The observable part only, so the menus don't stay disabled after a share sheet closes;
    // the action checks the rest when it runs.
    guard !targets.isCoveredObservably(), let action = targets.action(id) else { return nil }
    return action.guarded { !targets.isCovered() }
  }

  private func actionMenu(_ action: ScreenAction?, title: String, placeholder: ScreenAction? = nil) -> some View {
    Menu(title) {
      if case let .menu(entries) = (action ?? placeholder)?.content {
        ScreenActionMenuItems(entries: entries)
          .disabled(action == nil)
      }
    }
    .disabled(action == nil)
  }

  var body: some Commands {
    CommandGroup(replacing: .appSettings) {
      Button("Settings…", systemImage: "gearshape") { Nav.shared.activeTab = .settings }
        .keyboardShortcut(",")
      // From any tab, not only Me, where the toolbar has it.
      // Not while something covers the screens: Log Out's alert couldn't show over a sheet.
      actionMenu(targets.isCoveredObservably() ? nil : ScreenAction.switchAccount(selectedID: generalDefSettings.redditCredentialSelectedID)?.guarded { !targets.isCovered() }, title: "Accounts")
    }

    // Edit > Find. Not in place of the system's `.textEditing` items: on iPad that group never
    // shows, so neither does its shortcut.
    CommandGroup(after: .pasteboard) {
      Divider()
      // Not the screen behind a reply, a full-screen image or a sheet.
      Button("Find…", systemImage: "magnifyingglass") { targets.find() }
        .keyboardShortcut("f")
        // Without an account, the Search tab only says so.
        .disabled(targets.isCoveredObservably() || !targets.canFind())
    }

    // The top of the View menu.
    CommandGroup(before: .toolbar) {
      Button("Refresh", systemImage: "arrow.clockwise") { targets.refresh() }
        .keyboardShortcut("r")
        .disabled(!targets.canRefresh)

      // The feed's and the post's own menus, as in their toolbars. In this group: in a second
      // group before the toolbar's items, their actions never run on Mac.
      Divider()
      actionMenu(screenAction(.sortPosts), title: "Sort Posts", placeholder: .sortPosts(SubListingSortOption?.none) { _ in })
      actionMenu(screenAction(.feedOptions), title: "Feed Options", placeholder: .feedOptions(layout: .large, setLayout: { _ in }, filters: [], selected: nil, select: { _ in }))
      actionMenu(screenAction(.sortComments), title: "Sort Comments", placeholder: .sortComments(nil) { _ in })
    }

    CommandMenu("Go") {
      Button("Posts", systemImage: "doc.text.image") { Nav.shared.activeTab = .posts }
        .keyboardShortcut("1")
      Button("Inbox", systemImage: "bell") { Nav.shared.activeTab = .inbox }
        .keyboardShortcut("2")
      Button("Me", systemImage: "person") { Nav.shared.activeTab = .me }
        .keyboardShortcut("3")
      Button("Search", systemImage: "magnifyingglass") { Nav.shared.activeTab = .search }
        .keyboardShortcut("4")

      Divider()

      Button("Back", systemImage: "chevron.backward") { Nav.back() }
        .keyboardShortcut("[")
        .disabled(!Nav.shared.activeRouter.canGoBack)

      let info = screenAction(.subredditInfo)
      Button(info?.title ?? "About Subreddit", systemImage: "info.circle") { info?.perform() }
        .disabled(info == nil)
    }

    CommandMenu("Post") {
      Button("Previous Post", systemImage: "chevron.up") { targets.openAdjacentPost(-1) }
        .keyboardShortcut(.upArrow, modifiers: [.command, .option])
        .disabled(!targets.canOpenAdjacentPost(-1))
      Button("Next Post", systemImage: "chevron.down") { targets.openAdjacentPost(1) }
        .keyboardShortcut(.downArrow, modifiers: [.command, .option])
        .disabled(!targets.canOpenAdjacentPost(1))

      Divider()

      // Not the post behind a reply being written or a full-screen image.
      let post = targets.isCoveredObservably() ? nil : targets.openPost
      Button(post?.post?.data?.likes == true ? "Remove Upvote" : "Upvote", systemImage: "arrow.up") {
        if let post = post?.post, !targets.isCovered() {
          Task { _ = await post.vote(.up) }
        }
      }
      .keyboardShortcut("u", modifiers: [.command, .shift])
      // Reddit turns down votes on archived posts.
      .disabled(post?.post?.data == nil || post?.post?.data?.archived == true)
      Button(post?.post?.data?.likes == false ? "Remove Downvote" : "Downvote", systemImage: "arrow.down") {
        if let post = post?.post, !targets.isCovered() {
          Task { _ = await post.vote(.down) }
        }
      }
      .keyboardShortcut("d", modifiers: [.command, .shift])
      .disabled(post?.post?.data == nil || post?.post?.data?.archived == true)
      Button("Reply", systemImage: "arrowshape.turn.up.left") {
        if !targets.isCovered() {
          post?.reply?()
        }
      }
      .keyboardShortcut("r", modifiers: [.command, .shift])
      // Reddit turns down comments on archived and locked posts.
      .disabled(post?.reply == nil || post?.post?.data?.acceptsReplies != true)
    }
  }
}
