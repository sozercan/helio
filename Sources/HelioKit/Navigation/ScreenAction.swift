//
//  ScreenAction.swift
//  Helio
//
//  A screen's own actions, described once for the Mac window toolbar and the menu bar.
//

import Defaults
import SwiftUI

/// One of a screen's own actions, such as a feed's sort or its subreddit's info. The screen
/// registers it with `CommandTargets`; the menu bar (`NavCommands`) lists it, and on Mac the
/// window toolbar (`MacTabToolbar`) shows it above the screen's column. On iPhone and iPad the
/// screen's navigation bar keeps its own SwiftUI menus instead.
struct ScreenAction: Identifiable, Equatable {
  /// The navigation bar shows the screen's actions where the window toolbar doesn't.
  static let showsInNavigationBar: Bool = {
    #if targetEnvironment(macCatalyst)
      false
    #else
      true
    #endif
  }()

  /// A menu item. Equal when it looks the same, whatever its closure.
  indirect enum Entry: Equatable {
    /// An item with a checkmark while `isOn`.
    case choice(_ title: String, systemImage: String? = nil, isOn: Bool, select: () -> Void)
    case submenu(_ title: String, systemImage: String?, [Entry])
    /// Items set apart in their menu, under an optional heading.
    case section(_ title: String?, [Entry])

    static func == (lhs: Entry, rhs: Entry) -> Bool {
      switch (lhs, rhs) {
      case let (.choice(lt, li, lOn, _), .choice(rt, ri, rOn, _)): lt == rt && li == ri && lOn == rOn
      case let (.submenu(lt, li, le), .submenu(rt, ri, re)): lt == rt && li == ri && le == re
      case let (.section(lt, le), .section(rt, re)): lt == rt && le == re
      default: false
      }
    }
  }

  enum Content: Equatable {
    case button(() -> Void)
    case menu([Entry])

    static func == (lhs: Content, rhs: Content) -> Bool {
      switch (lhs, rhs) {
      case (.button, .button): true
      case let (.menu(l), .menu(r)): l == r
      default: false
      }
    }
  }

  enum ID: String {
    case sortPosts, feedOptions, sortComments, subredditInfo, switchAccount
  }

  var id: ID
  var title: String
  var systemImage: String
  var content: Content

  /// Runs a button action. Menus run their entries instead.
  func perform() {
    if case let .button(run) = content {
      run()
    }
  }

  /// The same action, doing nothing unless `allowed()` when it runs.
  func guarded(_ allowed: @escaping () -> Bool) -> ScreenAction {
    func guarded(_ entry: Entry) -> Entry {
      switch entry {
      case let .choice(title, systemImage, isOn, select): .choice(title, systemImage: systemImage, isOn: isOn) {
          if allowed() {
            select()
          }
        }
      case let .submenu(title, systemImage, entries): .submenu(title, systemImage: systemImage, entries.map(guarded))
      case let .section(title, entries): .section(title, entries.map(guarded))
      }
    }
    var action = self
    switch content {
    case let .button(run): action.content = .button {
        if allowed() {
          run()
        }
      }
    case let .menu(entries): action.content = .menu(entries.map(guarded))
    }
    return action
  }
}

extension ScreenAction {
  /// A feed's sort, with a checkmark on the current one; options with children (Top's time
  /// ranges) are submenus.
  static func sortPosts<S: Sorting>(_ sorting: S?, set: @escaping (S) -> Void) -> ScreenAction {
    let cases = Array(S.allCases)
    let flat: [Entry] = cases.filter { $0.meta.children == nil }.map { opt in
      .choice(opt.meta.label, systemImage: opt.meta.icon, isOn: sorting == opt) { set(opt) }
    }
    let nested: [Entry] = cases.filter { $0.meta.children != nil }.map { opt in
      .submenu(opt.meta.label, systemImage: opt.meta.icon, (opt.meta.children ?? []).compactMap { child in
        guard let value = child.valueWithParent as? S else { return nil }
        return .choice(child.meta.label, systemImage: child.meta.icon, isOn: sorting == value) { set(value) }
      })
    }
    return ScreenAction(id: .sortPosts, title: "Sort Posts", systemImage: sorting?.meta.icon ?? "arrow.up.arrow.down", content: .menu(flat + nested))
  }

  /// A subreddit feed's compact-posts switch and its flair filter.
  static func feedOptions(compact: Bool, setCompact: @escaping (Bool) -> Void, filters: [ShallowCachedFilter], selected: ShallowCachedFilter?, select: @escaping (ShallowCachedFilter?) -> Void) -> ScreenAction {
    var entries: [Entry] = [.choice("Compact Posts", systemImage: "rectangle.compress.vertical", isOn: compact) { setCompact(!compact) }]
    let shown = filters.filter { $0.type == .flair } + filters.filter { $0.type == .custom }
    if !shown.isEmpty {
      entries.append(.section("Flair", [.choice("All Posts", systemImage: "square.stack", isOn: selected == nil) { select(nil) }]
          // By kind and text, not colors, which a refresh can change while it's selected.
          + shown.map { filter in .choice(filter.text, isOn: selected?.pickerKey == filter.pickerKey) { select(filter) } }))
    }
    return ScreenAction(id: .feedOptions, title: "Feed Options", systemImage: selected == nil ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill", content: .menu(entries))
  }

  static func sortComments(_ sort: CommentSortOption?, set: @escaping (CommentSortOption) -> Void) -> ScreenAction {
    ScreenAction(id: .sortComments, title: "Sort Comments", systemImage: sort?.rawVal.icon ?? "arrow.up.arrow.down", content: .menu(CommentSortOption.allCases.map { opt in
      .choice(opt.rawVal.value.capitalized, systemImage: opt.rawVal.icon, isOn: sort == opt) { set(opt) }
    }))
  }

  /// Opens a subreddit's info, from the column the screen is in.
  static func subredditInfo(_ sub: Subreddit, column: Router.Column?) -> ScreenAction {
    ScreenAction(id: .subredditInfo, title: "About r/\(sub.data?.display_name ?? sub.id)", systemImage: "info.circle", content: .button {
      Nav.to(.reddit(.subInfo(sub)), from: column)
    })
  }

  /// Switches between the signed-in accounts. Nil with only one.
  /// Pass the observed selection where the caller watches it (the menu bar), so the check mark
  /// follows a switch made elsewhere.
  @MainActor
  static func switchAccount(manager: RedditCredentialsManager = .shared, selectedID: UUID? = nil) -> ScreenAction? {
    let credentials = manager.validCredentials
    guard credentials.count > 1 else { return nil }
    // The manager falls back to the first account when the stored one is gone (deleted).
    let selected = selectedID.map { manager.selectedCredential(id: $0)?.id } ?? manager.selectedCredential?.id
    return ScreenAction(id: .switchAccount, title: "Switch Account", systemImage: "person.2.circle", content: .menu(credentials.map { cred in
      .choice(cred.userName ?? "Account", isOn: cred.id == selected) {
        Defaults[.GeneralDefSettings].redditCredentialSelectedID = cred.id
      }
    }))
  }
}

/// A screen action's entries as menu items, for the menu bar.
struct ScreenActionMenuItems: View {
  var entries: [ScreenAction.Entry]

  var body: some View {
    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
      EntryItem(entry: entry)
    }
  }

  private struct EntryItem: View {
    var entry: ScreenAction.Entry

    var body: some View {
      switch entry {
      case let .choice(title, _, isOn, select):
        // Text only: on Mac, a menu bar toggle with an icon never runs its action.
        Toggle(title, isOn: Binding(get: { isOn }, set: { _ in select() }))
      case let .submenu(title, systemImage, entries):
        Menu {
          ScreenActionMenuItems(entries: entries)
        } label: {
          if let systemImage {
            Label(title, systemImage: systemImage)
          } else {
            Text(title)
          }
        }
      case let .section(title?, entries):
        Section(title) {
          ScreenActionMenuItems(entries: entries)
        }
      case let .section(nil, entries):
        Section {
          ScreenActionMenuItems(entries: entries)
        }
      }
    }
  }
}

/// How to turn one ordered list of toolbar items into another while keeping the items the two
/// share at either end, so the tabs and the sidebar button aren't rebuilt as screen actions come
/// and go: remove `current[range]`, then insert `insert` at `range.lowerBound`.
func toolbarEdit<T: Equatable>(from current: [T], to desired: [T]) -> (range: Range<Int>, insert: [T])? {
  guard current != desired else { return nil }
  var prefix = 0
  while prefix < current.count, prefix < desired.count, current[prefix] == desired[prefix] {
    prefix += 1
  }
  var suffix = 0
  while suffix < current.count - prefix, suffix < desired.count - prefix,
        current[current.count - 1 - suffix] == desired[desired.count - 1 - suffix]
  {
    suffix += 1
  }
  return (prefix ..< current.count - suffix, Array(desired[prefix ..< desired.count - suffix]))
}
