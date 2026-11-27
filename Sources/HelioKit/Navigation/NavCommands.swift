import Defaults
import SwiftUI

struct NavCommands: Commands {
  private let targets = CommandTargets.shared
  @Default(.GeneralDefSettings) private var generalDefSettings

  private func screenAction(_ id: ScreenAction.ID) -> ScreenAction? {
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
    #if targetEnvironment(macCatalyst)
      CommandGroup(after: .appInfo) {
        if MacUpdater.shared.isAvailable {
          Button("Check for Updates…") { MacUpdater.shared.checkForUpdates() }
            .disabled(!MacUpdater.shared.canCheckForUpdates)
        }
      }
    #endif

    CommandGroup(replacing: .appSettings) {
      Button("Settings…", systemImage: "gearshape") { Nav.shared.activeTab = .settings }
        .keyboardShortcut(",")
      actionMenu(targets.isCoveredObservably() ? nil : ScreenAction.switchAccount(selectedID: generalDefSettings.redditCredentialSelectedID)?.guarded { !targets.isCovered() }, title: "Accounts")
    }

    CommandGroup(after: .pasteboard) {
      Divider()
      Button("Find…", systemImage: "magnifyingglass") { targets.find() }
        .keyboardShortcut("f")
        .disabled(targets.isCoveredObservably() || !targets.canFind())
    }

    CommandGroup(before: .toolbar) {
      Button("Refresh", systemImage: "arrow.clockwise") { targets.refresh() }
        .keyboardShortcut("r")
        .disabled(!targets.canRefresh)

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

      let post = targets.isCoveredObservably() ? nil : targets.openPost
      Button(post?.post?.data?.likes == true ? "Remove Upvote" : "Upvote", systemImage: "arrow.up") {
        if let post = post?.post, !targets.isCovered() {
          Task { _ = await post.vote(.up) }
        }
      }
      .keyboardShortcut("u", modifiers: [.command, .shift])
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
      .disabled(post?.reply == nil || post?.post?.data?.acceptsReplies != true)
    }
  }
}
