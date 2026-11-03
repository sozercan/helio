//
//  NavCommands.swift
//  Helio
//

import SwiftUI

/// Menu bar items and keyboard shortcuts on Mac and on iPad with a hardware keyboard: the tabs,
/// Back, Refresh and Find, and the open post's. Shortcuts all take Command, so none of them
/// takes a key from a text field; the arrows also take Option, which text fields don't use.
struct NavCommands: Commands {
  private let targets = CommandTargets.shared

  var body: some Commands {
    CommandGroup(replacing: .appSettings) {
      Button("Settings…", systemImage: "gearshape") { Nav.shared.activeTab = .settings }
        .keyboardShortcut(",")
    }

    // Edit > Find. Not in place of the system's `.textEditing` items: on iPad that group never
    // shows, so neither does its shortcut.
    CommandGroup(after: .pasteboard) {
      Divider()
      // Not the screen behind a reply, a full-screen image or a sheet.
      Button("Find…", systemImage: "magnifyingglass") { targets.find() }
        .keyboardShortcut("f")
        .disabled(targets.isCoveredObservably())
    }

    // The top of the View menu.
    CommandGroup(before: .toolbar) {
      Button("Refresh", systemImage: "arrow.clockwise") { targets.refresh() }
        .keyboardShortcut("r")
        .disabled(!targets.canRefresh)
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
