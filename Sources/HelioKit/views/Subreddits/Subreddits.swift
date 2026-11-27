import Combine
import Defaults
import SwiftDate
import SwiftUI

#if targetEnvironment(macCatalyst)
  private let usesThemeBackgroundInSidebar = true
#else
  private let usesThemeBackgroundInSidebar = false
#endif

struct Subreddits: View, Equatable {
  static func == (lhs: Subreddits, rhs: Subreddits) -> Bool {
    lhs.loaded == rhs.loaded && lhs.currentCredentialID == rhs.currentCredentialID && lhs.inSidebar == rhs.inSidebar
  }

  @Binding var firstDestination: Router.NavDest?
  var loaded: Bool
  var currentCredentialID: UUID
  var inSidebar: Bool
  init(firstDestination: Binding<Router.NavDest?>, loaded: Bool, currentCredentialID: UUID, inSidebar: Bool) {
    self.currentCredentialID = currentCredentialID
    self._firstDestination = firstDestination
    self.loaded = loaded
    self.inSidebar = inSidebar
    self._subreddits = FetchRequest<CachedSub>(sortDescriptors: [NSSortDescriptor(key: "display_name", ascending: true)], predicate: NSPredicate(format: "helioCredentialID == %@", currentCredentialID as CVarArg), animation: .default)
    self._multis = FetchRequest<CachedMulti>(sortDescriptors: [NSSortDescriptor(key: "display_name", ascending: true)], predicate: NSPredicate(format: "helioCredentialID == %@", currentCredentialID as CVarArg), animation: .default)
  }

  @FetchRequest private var subreddits: FetchedResults<CachedSub>
  @FetchRequest private var multis: FetchedResults<CachedMulti>

  @State private var searchText: String = ""
  @State private var searchPresented = false
  @FocusState private var searchFocused: Bool

  @Default(.AppearanceDefSettings) private var appearanceDefSettings
  @Environment(\.useTheme) private var selectedTheme

  var sections: [String: [CachedSub]] {
    Dictionary(grouping: subreddits.filter(\.user_is_subscriber)) { sub in
      String((sub.display_name ?? "a").first!.uppercased())
    }
  }

  struct RowSelection: Hashable {
    var dest: Router.NavDest
    var inFavorites = false

    static func == (lhs: RowSelection, rhs: RowSelection) -> Bool {
      lhs.inFavorites == rhs.inFavorites && lhs.dest.isSameFeed(as: rhs.dest)
    }

    func hash(into hasher: inout Hasher) {
      hasher.combine(inFavorites)
      if let name = dest.subredditFeedName {
        hasher.combine(name)
      } else {
        hasher.combine(dest)
      }
    }

    static func row(for dest: Router.NavDest?, chosen: RowSelection?, favoriteShows: (Router.NavDest) -> Bool = { _ in true }) -> RowSelection? {
      guard let dest else { return nil }
      let inFavorites = chosen.map { $0.inFavorites && $0.dest.isSameFeed(as: dest) } == true && favoriteShows(dest)
      return RowSelection(dest: dest, inFavorites: inFavorites)
    }
  }

  @State private var chosenRow: RowSelection?

  private var selection: Binding<RowSelection?> {
    Binding {
      RowSelection.row(for: firstDestination, chosen: chosenRow, favoriteShows: favoriteRowShows)
    } set: { row in
      if let row {
        chosenRow = row
      }
      firstDestination = row?.dest
    }
  }

  private func favoriteRowShows(_ dest: Router.NavDest) -> Bool {
    guard searchText.isEmpty, let name = dest.subredditFeedName else { return false }
    return subreddits.contains { $0.user_has_favorited && $0.user_is_subscriber && $0.display_name?.lowercased() == name }
  }

  private func subItem(_ cachedSub: CachedSub, inFavorites: Bool = false, selected: RowSelection?) -> some View {
    let sub = Subreddit(data: SubredditData(entity: cachedSub))
    let row = RowSelection(dest: .reddit(.subFeed(sub)), inFavorites: inFavorites)
    return SubItem(isActive: row == selected, inSidebar: inSidebar, sub: sub, cachedSub: cachedSub) {
      selection.wrappedValue = row
    }
    .tag(row)
  }

  private func feedTile(_ label: String, icon: String, color: Color, id: String) -> some View {
    let dest = Router.NavDest.reddit(.subFeed(Subreddit(id: id)))
    return ListBigBtn(icon: icon, iconColor: color, label: label, selected: dest == firstDestination) {
      firstDestination = dest
    }
  }

  var body: some View {
    let selectedRow = selection.wrappedValue
    List(selection: selection) {
      if searchText.isEmpty {
        VStack(spacing: 12) {
          HStack(spacing: 12) {
            feedTile("Home", icon: "house.circle.fill", color: .blue, id: "home")
            feedTile("Popular", icon: "chart.line.uptrend.xyaxis.circle.fill", color: .red, id: "popular")
          }
          HStack(spacing: 12) {
            feedTile("All", icon: "signpost.right.and.left.circle.fill", color: .orange, id: "all")
            feedTile("Saved", icon: "bookmark.circle.fill", color: .green, id: savedKeyword)
          }
        }
        .environment(\.isInSidebar, false)
        .frame(maxWidth: .infinity)
        .id("bigButtons")
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

        if !multis.isEmpty {
          Section("Multis") {
            ScrollView(.horizontal) {
              HStack(spacing: 16) {
                ForEach(multis) { multi in
                  let multi = Multi(data: MultiData(entity: multi))
                  MultiLink(multi: multi, selected: firstDestination == .reddit(.multiFeed(multi)))
                }
              }
              .padding(.horizontal, 16)
            }
          }
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
      }

      Group {
        if !searchText.isEmpty {
          Section("Found subs") {
            let foundSubs = Array(Array(subreddits.filter { ($0.display_name ?? "").lowercased().contains(searchText.lowercased()) }).enumerated())
            ForEach(foundSubs, id: \.self.element.uuid) { _, cachedSub in
              subItem(cachedSub, selected: selectedRow)
            }
          }

        } else {
          let favs = subreddits.filter { $0.user_has_favorited && $0.user_is_subscriber }
          if !favs.isEmpty {
            Section("Favorites") {
              let favs = Array(favs.sorted(by: { x, y in (x.display_name?.lowercased() ?? "a") < (y.display_name?.lowercased() ?? "a") }).enumerated())
              ForEach(favs, id: \.self.element) { _, cachedSub in
                subItem(cachedSub, inFavorites: true, selected: selectedRow)
                  .id("\(cachedSub.uuid ?? "")-fav")
              }
              .onDelete(perform: deleteFromFavorites)
            }
          }

          if appearanceDefSettings.disableAlphabetLettersSectionsInSubsList {
            Section("Subs") {
              let subs = Array(subreddits.filter(\.user_is_subscriber).sorted(by: { x, y in (x.display_name?.lowercased() ?? "a") < (y.display_name?.lowercased() ?? "a") }).enumerated())
              ForEach(subs, id: \.self.element) { _, cachedSub in
                subItem(cachedSub, selected: selectedRow)
              }
            }

          } else {
            ForEach(sections.keys.sorted(), id: \.self) { letter in
              Section(header: Text(letter)) {
                if let arr = sections[letter] {
                  let subs = Array(arr.sorted(by: { x, y in
                    (x.display_name?.lowercased() ?? "a") < (y.display_name?.lowercased() ?? "a")
                  }).enumerated())
                  ForEach(subs, id: \.self.element.uuid) { _, cachedSub in
                    subItem(cachedSub, selected: selectedRow)
                  }
                  .onDelete(perform: { i in
                    deleteFromList(at: i, letter: letter)
                  })
                }
              }
              .sectionIndexLabel(letter)
            }
          }
        }
      }
      .themedListSection(disable: usesThemeBackgroundInSidebar || inSidebar)
    }
    .environment(\.isInSidebar, true)
    .themedListBG(selectedTheme.lists.bg, disable: inSidebar && !usesThemeBackgroundInSidebar, keepSystemBackground: inSidebar && !usesThemeBackgroundInSidebar)
    .touchScrollIndicators(.hidden)
    .listStyle(.sidebar)
    .scrollDismissesKeyboard(.immediately)
    .loader(!loaded && subreddits.isEmpty)
    .subsSearchAndEdit($searchText, isPresented: $searchPresented, focused: $searchFocused)
    .commandTarget(CommandTargets.Target(kind: .subs, refresh: { Task { await refresh() } }, focusSearch: {
      searchPresented = true
      searchFocused = true
    }))
    .overlay(alignment: .trailing) {
      if usesThemeBackgroundInSidebar {
        Color(uiColor: .separator).frame(width: 1).ignoresSafeArea()
      }
    }
    #if targetEnvironment(macCatalyst)
    .listSectionIndexVisibility(.hidden)
    #endif
    .refreshable { await refresh() }
    .navigationTitle("Subreddits")
  }

  private func refresh() async {
    Task(priority: .utility) {
      _ = await RedditAPI.shared.fetchMyMultis()
    }
    _ = await RedditAPI.shared.fetchSubsAndSyncCoreData()
  }

  func deleteFromFavorites(at offsets: IndexSet) {
    for i in offsets {
      Task(priority: .background) {
        Subreddit(data: SubredditData(entity: subreddits.filter { $0.user_has_favorited && $0.user_is_subscriber }.sorted(by: { x, y in (x.display_name?.lowercased() ?? "a") < (y.display_name?.lowercased() ?? "a") })[i])).subscribeToggle(optimistic: true)
      }
    }
  }

  func deleteFromList(at offsets: IndexSet, letter: String) {
    for i in offsets {
      if let sub = sections[letter]?.sorted(by: { x, y in
        (x.display_name?.lowercased() ?? "a") < (y.display_name?.lowercased() ?? "a")
      })[i] {
        Task(priority: .background) {
          Subreddit(data: SubredditData(entity: sub)).subscribeToggle(optimistic: true)
        }
      }
    }
  }
}

private extension View {
  func subsSearchAndEdit(_ searchText: Binding<String>, isPresented: Binding<Bool>, focused: FocusState<Bool>.Binding) -> some View {
    #if targetEnvironment(macCatalyst)
      safeAreaBar(edge: .top, spacing: 0) { MacSubsHeader(searchText: searchText, focusRequested: isPresented) }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .toolbar(.hidden, for: .navigationBar)
    #else
      searchable(text: searchText, isPresented: isPresented, prompt: "Search my subreddits")
        .searchFocused(focused)
        .toolbar {
          ToolbarItem(placement: .navigationBarTrailing) {
            EditButton()
          }
        }
    #endif
  }
}

#if targetEnvironment(macCatalyst)
  private struct MacSubsHeader: View {
    @Binding var searchText: String
    @Binding var focusRequested: Bool
    @FocusState private var focused: Bool

    var body: some View {
      HStack(spacing: 10) {
        HStack(spacing: 6) {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(.secondary)
          TextField("Search my subreddits", text: $searchText)
            .focused($focused)
            .onChange(of: focusRequested) { _, requested in
              if requested {
                focused = true
                focusRequested = false
              }
            }
            .textFieldStyle(.plain)
            .focusEffectDisabled()
          if !searchText.isEmpty {
            Button("Clear search", systemImage: "xmark.circle.fill") { searchText = "" }
              .labelStyle(.iconOnly)
              .buttonStyle(.borderless)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())

        EditButton()
          .buttonStyle(.borderless)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
    }
  }
#endif
