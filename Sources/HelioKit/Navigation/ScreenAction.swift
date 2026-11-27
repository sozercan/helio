import Defaults
import SwiftUI

struct ScreenAction: Identifiable, Equatable {
  static let showsInNavigationBar: Bool = {
    #if targetEnvironment(macCatalyst)
      false
    #else
      true
    #endif
  }()

  indirect enum Entry: Equatable {
    case choice(_ title: String, systemImage: String? = nil, isOn: Bool, select: () -> Void)
    case submenu(_ title: String, systemImage: String?, [Entry])
    case section(_ title: String?, [Entry])

    static func at(_ path: [Int], in entries: [Entry]) -> Entry? {
      guard let index = path.first, entries.indices.contains(index) else { return nil }
      let entry = entries[index]
      guard path.count > 1 else { return entry }
      switch entry {
      case .choice: return nil
      case let .submenu(_, _, children), let .section(_, children): return at(Array(path.dropFirst()), in: children)
      }
    }

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
    case sortPosts, feedOptions, sortComments, subredditInfo, switchAccount, openInBrowser
  }

  var id: ID
  var title: String
  var systemImage: String
  var content: Content

  func perform() {
    if case let .button(run) = content {
      run()
    }
  }

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

  static func feedOptions(layout: PostLayout, layouts: [PostLayout] = PostLayout.allCases, setLayout: @escaping (PostLayout) -> Void, filters: [ShallowCachedFilter], selected: ShallowCachedFilter?, select: @escaping (ShallowCachedFilter?) -> Void) -> ScreenAction {
    var entries: [Entry] = [.section(nil, layouts.map { option in
      .choice(option.title, systemImage: option.systemImage, isOn: layout == option) { setLayout(option) }
    })]
    var seen = Set<String>()
    let shown = (filters.filter { $0.type == .flair } + filters.filter { $0.type == .custom })
      .filter { seen.insert($0.pickerKey).inserted }
    if !shown.isEmpty || selected != nil {
      entries.append(.section("Flair", [.choice("All Posts", systemImage: "square.stack", isOn: selected == nil) { select(nil) }]
          + shown.map { filter in .choice(filter.text, isOn: selected?.pickerKey == filter.pickerKey) { select(filter) } }))
    }
    return ScreenAction(id: .feedOptions, title: "Feed Options", systemImage: selected == nil ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill", content: .menu(entries))
  }

  static func sortComments(_ sort: CommentSortOption?, set: @escaping (CommentSortOption) -> Void) -> ScreenAction {
    ScreenAction(id: .sortComments, title: "Sort Comments", systemImage: sort?.rawVal.icon ?? "arrow.up.arrow.down", content: .menu(CommentSortOption.allCases.map { opt in
      .choice(opt.rawVal.value.capitalized, systemImage: opt.rawVal.icon, isOn: sort == opt) { set(opt) }
    }))
  }

  static func subredditInfo(_ sub: Subreddit, column: Router.Column?) -> ScreenAction {
    ScreenAction(id: .subredditInfo, title: "About r/\(sub.data?.display_name ?? sub.id)", systemImage: "info.circle", content: .button {
      Nav.to(.reddit(.subInfo(sub)), from: column)
    })
  }

  static func openInBrowser(_ url: URL) -> ScreenAction {
    ScreenAction(id: .openInBrowser, title: "Open in Browser", systemImage: "safari", content: .button {
      UIApplication.shared.open(url)
    })
  }

  @MainActor
  static func switchAccount(
    manager: RedditCredentialsManager = .shared,
    selectedID: UUID? = nil,
    addAccount: @escaping @MainActor () -> Void = { Nav.present(.editingCredential(.init())) },
    logOut: @escaping @MainActor (RedditCredential) -> Void = { LogOutConfirmation.shared.ask($0) },
  ) -> ScreenAction? {
    guard let selected = selectedID.map({ manager.selectedCredential(id: $0) }) ?? manager.selectedCredential else { return nil }
    let credentials = manager.validCredentials
    var entries: [Entry] = []
    if credentials.contains(where: { $0.id != selected.id }) {
      entries.append(.section(nil, credentials.map { cred in
        .choice(cred.userName ?? "Account", isOn: cred.id == selected.id) {
          Defaults[.GeneralDefSettings].redditCredentialSelectedID = cred.id
        }
      }))
    }
    entries.append(.section(nil, [.choice("Add Account", systemImage: "person.badge.plus", isOn: false) {
      addAccount()
    }]))
    entries.append(.section(nil, [.choice(LogOutConfirmation.title(selected), systemImage: "rectangle.portrait.and.arrow.right", isOn: false) {
      logOut(selected)
    }]))
    return ScreenAction(id: .switchAccount, title: "Accounts", systemImage: "person.2.circle", content: .menu(entries))
  }
}

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
