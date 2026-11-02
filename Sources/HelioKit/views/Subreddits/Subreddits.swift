//
//  Subreddits.swift
//  Helio
//
//  Created by Igor Marcossi on 24/06/23.
//

import Combine
import Defaults
import SwiftDate
import SwiftUI

// Mac windows paint the subs list with the window background instead of the theme's, so it
// continues the title bar above it rather than starting below it in another shade.
#if targetEnvironment(macCatalyst)
  private let usesWindowBackground = true
#else
  private let usesWindowBackground = false
#endif

struct Subreddits: View, Equatable {
  static func == (lhs: Subreddits, rhs: Subreddits) -> Bool {
    lhs.loaded == rhs.loaded && lhs.currentCredentialID == rhs.currentCredentialID && lhs.inSidebar == rhs.inSidebar
  }

  /// The feed shown beside the list, which the list shows as its selection.
  @Binding var firstDestination: Router.NavDest?
  var loaded: Bool
  var currentCredentialID: UUID
  /// Shown as the split view's sidebar, beside the feed, rather than as the first screen of a stack.
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

//    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "display_name", ascending: true)])
//    private var subreddits: FetchedResults<CachedSub>
//
//    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "display_name", ascending: true)])
//    private var multis: FetchedResults<CachedMulti>

  @State private var searchText: String = ""
  /// The search field's state, which the menu bar's Find sets.
  @State private var searchPresented = false

  //  @Default(.likedButNotSubbed) private var likedButNotSubbed // subreddits that a user likes but is not subscribed to so they wont be in subsDict
  @Default(.AppearanceDefSettings) private var appearanceDefSettings
  @Environment(\.useTheme) private var selectedTheme

  var sections: [String: [CachedSub]] {
    Dictionary(grouping: subreddits.filter(\.user_is_subscriber)) { sub in
      String((sub.display_name ?? "a").first!.uppercased())
    }
  }

  /// A row the list can select: its feed, and whether it's the row in Favorites, as a favorite
  /// shows twice. Selecting either opens the same feed.
  struct RowSelection: Hashable {
    var dest: Router.NavDest
    var inFavorites = false

    /// The row that shows `dest` as selected: the one chosen last if it shows `dest`, else its
    /// row outside Favorites, as when the feed was opened from elsewhere.
    static func row(for dest: Router.NavDest?, chosen: RowSelection?) -> RowSelection? {
      guard let dest else { return nil }
      if let chosen, chosen.dest.isSameFeed(as: dest) {
        return chosen
      }
      return RowSelection(dest: dest)
    }
  }

  /// The row chosen last, which tells a favorite's two rows apart.
  @State private var chosenRow: RowSelection?

  private var selection: Binding<RowSelection?> {
    Binding {
      RowSelection.row(for: firstDestination, chosen: chosenRow)
    } set: { row in
      if let row {
        chosenRow = row
      }
      firstDestination = row?.dest
    }
  }

  /// A subreddit's row, tagged with its feed so the list's selection opens it.
  private func subItem(_ cachedSub: CachedSub, inFavorites: Bool = false) -> some View {
    let sub = Subreddit(data: SubredditData(entity: cachedSub))
    let row = RowSelection(dest: .reddit(.subFeed(sub)), inFavorites: inFavorites)
    return SubItem(isActive: row == selection.wrappedValue, inSidebar: inSidebar, sub: sub, cachedSub: cachedSub) {
      selection.wrappedValue = row
    }
    .tag(row)
  }

  /// A feed's tile, selected while its feed shows.
  private func feedTile(_ label: String, icon: String, color: Color, id: String) -> some View {
    let dest = Router.NavDest.reddit(.subFeed(Subreddit(id: id)))
    return ListBigBtn(icon: icon, iconColor: color, label: label, selected: dest == firstDestination) {
      firstDestination = dest
    }
  }

  var body: some View {
    ScrollViewReader { proxy in
      List(selection: selection) {
        if searchText == "" {
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

          //          Section{
          //            UpsellCard(upsellName: "themesUpsell_01", {
          //                Text("Tired of Helios current look? Try the theme editor in settings now!")
          //                .helioShiny()
          //              .fontWeight(.semibold)
          //              .font(.system(size: 15))
          //            })
          //            .padding()
          //          }
          //          .listRowSeparator(.hidden)
          ////            .listRowBackground(Color.clear)
          //          .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

          PostsInBoxView()
            .scrollIndicators(.hidden)
            //            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)

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
          if searchText != "" {
            Section("Found subs") {
              let foundSubs = Array(Array(subreddits.filter { ($0.display_name ?? "").lowercased().contains(searchText.lowercased()) }).enumerated())
              ForEach(foundSubs, id: \.self.element.uuid) { _, cachedSub in
                subItem(cachedSub)
              }
            }

          } else {
            let favs = subreddits.filter { $0.user_has_favorited && $0.user_is_subscriber }
            if !favs.isEmpty {
              Section("Favorites") {
                let favs = Array(favs.sorted(by: { x, y in (x.display_name?.lowercased() ?? "a") < (y.display_name?.lowercased() ?? "a") }).enumerated())
                ForEach(favs, id: \.self.element) { _, cachedSub in
                  subItem(cachedSub, inFavorites: true)
                    .id("\(cachedSub.uuid ?? "")-fav")
                }
                .onDelete(perform: deleteFromFavorites)
              }
            }

            if appearanceDefSettings.disableAlphabetLettersSectionsInSubsList {
              Section("Subs") {
                let subs = Array(subreddits.filter(\.user_is_subscriber).sorted(by: { x, y in (x.display_name?.lowercased() ?? "a") < (y.display_name?.lowercased() ?? "a") }).enumerated())
                ForEach(subs, id: \.self.element) { _, cachedSub in
                  subItem(cachedSub)
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
                      subItem(cachedSub)
                    }
                    .onDelete(perform: { i in
                      deleteFromList(at: i, letter: letter)
                    })
                  }
                }
              }
            }
          }
        }
        // A sidebar's rows are the system's, which draw its selection.
        .themedListSection(disable: usesWindowBackground || inSidebar)
      }
      .environment(\.isInSidebar, true)
      // On iPad, the sidebar's own material instead of the theme's background.
      .themedListBG(selectedTheme.lists.bg, disable: usesWindowBackground || inSidebar, keepSystemBackground: inSidebar && !usesWindowBackground)
      .background {
        if usesWindowBackground {
          Color(uiColor: .systemBackground).ignoresSafeArea()
        }
      }
      .scrollIndicators(.hidden)
      .listStyle(.sidebar)
      .scrollDismissesKeyboard(.immediately)
      .loader(!loaded && subreddits.isEmpty)
      .subsSearchAndEdit($searchText, isPresented: $searchPresented)
      .commandTarget(CommandTargets.Target(kind: .subs, refresh: { Task { await refresh() } }, focusSearch: { searchPresented = true }))
      .overlay(alignment: .trailing) {
        // Without the sidebar's own shade, a hairline marks where the posts start.
        if usesWindowBackground {
          Color(uiColor: .separator).frame(width: 1).ignoresSafeArea()
        }
      }
      #if !targetEnvironment(macCatalyst)
      // A touch control: on Mac, the pointer scrolls. Only while the list shows its letter
      // sections: filtered or without them, there's nothing for a letter to scroll to.
      .overlay(alignment: .trailing) {
        AlphabetJumper(letters: searchText.isEmpty && !appearanceDefSettings.disableAlphabetLettersSectionsInSubsList ? sections.keys.sorted() : [], proxy: proxy)
      }
      #endif
      .refreshable { await refresh() }
      .navigationTitle("Subs")
    }
  }

  private func refresh() async {
    Task(priority: .utility) {
      await updatePostsInBox(force: true)
    }
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

// struct Posts_Previews: PreviewProvider {
//  static var previews: some View {
//    Posts()
//  }
// }

private extension View {
  /// The subs list's search field and Edit button. iOS keeps them in the navigation bar. On Mac
  /// that bar floats over the rows, which show through behind it, so the list gets a plain
  /// header above it instead.
  @ViewBuilder
  func subsSearchAndEdit(_ searchText: Binding<String>, isPresented: Binding<Bool>) -> some View {
    #if targetEnvironment(macCatalyst)
      safeAreaInset(edge: .top, spacing: 0) { MacSubsHeader(searchText: searchText, focusRequested: isPresented) }
        .toolbar(.hidden, for: .navigationBar)
    #else
      searchable(text: searchText, isPresented: isPresented, prompt: "Search my subreddits")
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
    /// Set by the menu bar's Find: focuses the field.
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
            // The capsule is the field; a focus ring inside it would be a second outline.
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
      .background(Color(uiColor: .systemBackground))
    }
  }
#endif
