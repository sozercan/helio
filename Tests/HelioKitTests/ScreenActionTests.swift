import Testing
@testable import HelioKit

struct ScreenActionTests {
  private func sort(_ title: String) -> ScreenAction {
    ScreenAction(id: .sortPosts, title: title, systemImage: "flame", content: .menu([]))
  }

  @Test func actionsComeFromTheScreenShownLastInEachColumn() {
    let targets = CommandTargets()
    _ = targets.register(.init(kind: .feed, column: .feed, actions: [sort("first feed")]))
    let second = targets.register(.init(kind: .feed, column: .feed, actions: [sort("second feed")]))
    _ = targets.register(.init(kind: .post, column: .post, actions: [sort("post")]))
    // A screen without actions, such as a user's page, doesn't hide the feed's.
    _ = targets.register(.init(kind: .feed, column: .feed))
    #expect(targets.actions(in: .feed).map(\.title) == ["second feed"])
    #expect(targets.actions(in: .post).map(\.title) == ["post"])
    #expect(targets.actions(in: nil).isEmpty)
    targets.unregister(second)
    #expect(targets.actions(in: .feed).map(\.title) == ["first feed"])
  }

  @Test func theMenuBarUsesTheActionOfTheScreenShownLast() {
    let targets = CommandTargets()
    let info = ScreenAction(id: .subredditInfo, title: "About r/apple", systemImage: "info.circle", content: .button {})
    _ = targets.register(.init(kind: .feed, column: .feed, actions: [sort("feed"), info]))
    let post = targets.register(.init(kind: .post, column: .post, actions: [ScreenAction(id: .subredditInfo, title: "About r/pics", systemImage: "info.circle", content: .button {})]))
    #expect(targets.action(.subredditInfo)?.title == "About r/pics")
    #expect(targets.action(.sortPosts)?.title == "feed")
    #expect(targets.action(.sortComments) == nil)
    targets.unregister(post)
    #expect(targets.action(.subredditInfo)?.title == "About r/apple")
  }

  @Test func updatingATargetChangesItsActionsInPlace() {
    let targets = CommandTargets()
    let id = targets.register(.init(kind: .feed, column: .feed, actions: [sort("hot")]))
    _ = targets.register(.init(kind: .post, column: .post))
    targets.update(id, to: .init(kind: .feed, column: .feed, actions: [sort("new")]))
    #expect(targets.actions(in: .feed).map(\.title) == ["new"])
    #expect(targets.targets.map(\.target.kind) == [.feed, .post])
  }

  @Test func actionsAreEqualWhenTheyLookTheSame() {
    let a = ScreenAction.sortComments(.confidence) { _ in }
    let b = ScreenAction.sortComments(.confidence) { _ in }
    let c = ScreenAction.sortComments(.new) { _ in }
    #expect(a == b)
    #expect(a != c)
  }

  @Test func theCommentSortChecksTheCurrentSort() {
    let action = ScreenAction.sortComments(.new) { _ in }
    guard case let .menu(entries) = action.content else {
      Issue.record("Expected a menu")
      return
    }
    let checked = entries.compactMap { entry -> String? in
      if case let .choice(title, _, isOn, _) = entry, isOn {
        title
      } else {
        nil
      }
    }
    #expect(checked == [CommentSortOption.new.rawVal.value.capitalized])
  }

  @Test func feedOptionsListEachFlairOnceAndKeepAllPostsWhileFiltered() {
    func flair(_ text: String, _ type: CachedFilter.FilterType, color: String? = nil) -> ShallowCachedFilter {
      ShallowCachedFilter(bgColor: color, subID: "apple", text: text, textColor: nil, rawType: type.rawValue)
    }
    func flairChoices(_ action: ScreenAction) -> [String]? {
      guard case let .menu(entries) = action.content else { return nil }
      for entry in entries {
        if case let .section(title, items) = entry, title == "Flair" {
          return items.compactMap {
            if case let .choice(title, _, _, _) = $0 {
              title
            } else {
              nil
            }
          }
        }
      }
      return nil
    }
    let duplicated = ScreenAction.feedOptions(layout: .large, setLayout: { _ in }, filters: [flair("News", .flair, color: "#ff0000"), flair("News", .flair, color: "#00ff00")], selected: nil, select: { _ in })
    #expect(flairChoices(duplicated) == ["All Posts", "News"])
    // A refresh made the selected flair moderator-only, so no flair is listed, but it's still on.
    let selected = flair("News", .modFlair)
    let filtered = ScreenAction.feedOptions(layout: .large, setLayout: { _ in }, filters: [selected], selected: selected, select: { _ in })
    #expect(flairChoices(filtered) == ["All Posts"])
    let unfiltered = ScreenAction.feedOptions(layout: .large, setLayout: { _ in }, filters: [selected], selected: nil, select: { _ in })
    #expect(flairChoices(unfiltered) == nil)
  }

  @Test func feedSortsWithChildrenAreSubmenus() {
    var picked: SubListingSortOption?
    let action = ScreenAction.sortPosts(SubListingSortOption.best) { picked = $0 }
    guard case let .menu(entries) = action.content else {
      Issue.record("Expected a menu")
      return
    }
    let submenus = entries.filter {
      if case .submenu = $0 {
        true
      } else {
        false
      }
    }
    #expect(submenus.count == SubListingSortOption.allCases.count { $0.meta.children != nil })
    // Best comes first, checked.
    if case let .choice(_, _, isOn, select) = entries.first {
      #expect(isOn)
      select()
    }
    #expect(picked == .best)
  }

  @Test func toolbarEditsKeepTheItemsAtEitherEnd() {
    let tabs = "tabs", toggle = "toggle", flex = "flex"
    // Actions appear between the sidebar button and the tabs.
    let edit = toolbarEdit(from: [toggle, flex, tabs], to: [toggle, flex, "sort", "info", tabs])
    #expect(edit?.range == 2 ..< 2)
    #expect(edit?.insert == ["sort", "info"])
    // And go again.
    let back = toolbarEdit(from: [toggle, flex, "sort", "info", tabs], to: [toggle, flex, tabs])
    #expect(back?.range == 2 ..< 4)
    #expect(back?.insert == [])
    // Another tab drops the sidebar button but keeps the tabs.
    let otherTab = toolbarEdit(from: [toggle, flex, tabs], to: ["account", flex, tabs])
    #expect(otherTab?.range == 0 ..< 1)
    #expect(otherTab?.insert == ["account"])
    #expect(toolbarEdit(from: [flex, tabs], to: [flex, tabs]) == nil)
  }

  @Test func toolbarEditsHandleRepeatedItems() {
    let current = ["toggle", "sep1", "flex", "sep2", "flex", "tabs"]
    let desired = ["toggle", "sep1", "flex", "sort", "sep2", "flex", "sort2", "space", "tabs"]
    guard let edit = toolbarEdit(from: current, to: desired) else {
      Issue.record("Expected an edit")
      return
    }
    var result = current
    result.replaceSubrange(edit.range, with: edit.insert)
    #expect(result == desired)
  }

  @Test func findsAMenuEntryByItsPath() {
    let entries: [ScreenAction.Entry] = [
      .choice("Hot", isOn: true) {},
      .section("Top", [.choice("Today", isOn: false) {}, .submenu("More", systemImage: nil, [.choice("All time", isOn: false) {}])]),
    ]
    func title(_ path: [Int]) -> String? {
      switch ScreenAction.Entry.at(path, in: entries) {
      case let .choice(title, _, _, _)?: title
      case let .submenu(title, _, _)?: title
      case let .section(title, _)?: title
      case nil: nil
      }
    }
    #expect(title([0]) == "Hot")
    #expect(title([1, 0]) == "Today")
    #expect(title([1, 1, 0]) == "All time")
    #expect(title([2]) == nil)
    #expect(title([0, 0]) == nil)
  }

  @MainActor
  @Test func theAccountsMenuListsOtherAccountsOnlyWhenThereAreAnyAndAlwaysLogsOut() {
    func account(_ name: String, signedIn: Bool = true) -> RedditCredential {
      RedditCredential(apiAppID: "placeholder-client-id", refreshToken: signedIn ? "placeholder-refresh-token" : nil, userName: name)
    }
    func titles(_ action: ScreenAction?) -> [[String]] {
      guard case let .menu(entries)? = action?.content else { return [] }
      return entries.map { entry in
        guard case let .section(_, items) = entry else { return [] }
        return items.compactMap {
          if case let .choice(title, _, _, _) = $0 {
            title
          } else {
            nil
          }
        }
      }
    }

    #expect(ScreenAction.switchAccount(manager: RedditCredentialsManager(credentials: [])) == nil)

    let only = account("placeholder-one")
    var loggedOut: RedditCredential?
    let single = ScreenAction.switchAccount(manager: RedditCredentialsManager(credentials: [only]), selectedID: only.id) { loggedOut = $0 }
    #expect(titles(single) == [["Log Out u/placeholder-one"]])
    guard case let .menu(entries)? = single?.content, case let .section(_, items)? = entries.last,
          case let .choice(_, _, isOn, select)? = items.first
    else {
      Issue.record("Expected a Log Out item")
      return
    }
    #expect(!isOn)
    select()
    #expect(loggedOut == only)

    let other = account("placeholder-two")
    let two = ScreenAction.switchAccount(manager: RedditCredentialsManager(credentials: [only, other]), selectedID: other.id) { _ in }
    #expect(titles(two) == [["placeholder-one", "placeholder-two"], ["Log Out u/placeholder-two"]])

    // Reddit signed the selected account out: the other one is still offered.
    let signedOut = account("placeholder-signed-out", signedIn: false)
    let fallback = ScreenAction.switchAccount(manager: RedditCredentialsManager(credentials: [signedOut, other]), selectedID: signedOut.id) { _ in }
    #expect(titles(fallback) == [["placeholder-two"], ["Log Out u/placeholder-signed-out"]])
  }
}
