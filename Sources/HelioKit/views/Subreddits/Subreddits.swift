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

let alphabetLetters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map { String($0) }

// Mac windows paint the subs list with the window background instead of the theme's, so it
// continues the title bar above it rather than starting below it in another shade.
#if targetEnvironment(macCatalyst)
  private let usesWindowBackground = true
#else
  private let usesWindowBackground = false
#endif

struct Subreddits: View, Equatable {
  static func == (lhs: Subreddits, rhs: Subreddits) -> Bool {
    lhs.loaded == rhs.loaded && lhs.currentCredentialID == rhs.currentCredentialID
  }

//  @State
  @Binding var firstDestination: Router.NavDest?
  var loaded: Bool
  var currentCredentialID: UUID
  init(firstDestination: Binding<Router.NavDest?>, loaded: Bool, currentCredentialID: UUID) {
    self.currentCredentialID = currentCredentialID
    self._firstDestination = firstDestination
    self.loaded = loaded
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

  //  @Default(.likedButNotSubbed) private var likedButNotSubbed // subreddits that a user likes but is not subscribed to so they wont be in subsDict
  @Default(.AppearanceDefSettings) private var appearanceDefSettings
  @Environment(\.managedObjectContext) private var context
  @Environment(\.useTheme) private var selectedTheme

  var sections: [String: [CachedSub]] {
    Dictionary(grouping: subreddits.filter(\.user_is_subscriber)) { sub in
      String((sub.display_name ?? "a").first!.uppercased())
    }
  }

  func selectSub(_ sub: Subreddit) {
    firstDestination = .reddit(.subFeed(sub))
  }

  var body: some View {
    ScrollViewReader { proxy in
      List(selection: $firstDestination) {
        if searchText == "" {
          VStack(spacing: 12) {
            HStack(spacing: 12) {
              ListBigBtn(icon: "house.circle.fill", iconColor: .blue, label: "Home") {
                firstDestination = .reddit(.subFeed(Subreddit(id: "home")))
              }

              ListBigBtn(icon: "chart.line.uptrend.xyaxis.circle.fill", iconColor: .red, label: "Popular") {
                firstDestination = .reddit(.subFeed(Subreddit(id: "popular")))
              }
            }
            HStack(spacing: 12) {
              ListBigBtn(icon: "signpost.right.and.left.circle.fill", iconColor: .orange, label: "All") {
                firstDestination = .reddit(.subFeed(Subreddit(id: "all")))
              }

              ListBigBtn(icon: "bookmark.circle.fill", iconColor: .green, label: "Saved") {
                firstDestination = .reddit(.subFeed(Subreddit(id: savedKeyword)))
              }
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
                    MultiLink(multi: Multi(data: MultiData(entity: multi)))
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
                let sub = Subreddit(data: SubredditData(entity: cachedSub))
                SubItem(isActive: Router.NavDest.reddit(.subFeed(sub)) == firstDestination, sub: sub, cachedSub: cachedSub, action: selectSub)
              }
            }

          } else {
            let favs = subreddits.filter { $0.user_has_favorited && $0.user_is_subscriber }
            if !favs.isEmpty {
              Section("Favorites") {
                let favs = Array(favs.sorted(by: { x, y in (x.display_name?.lowercased() ?? "a") < (y.display_name?.lowercased() ?? "a") }).enumerated())
                ForEach(favs, id: \.self.element) { _, cachedSub in
                  let sub = Subreddit(data: SubredditData(entity: cachedSub))
                  SubItem(isActive: Router.NavDest.reddit(.subFeed(sub)) == firstDestination, sub: sub, cachedSub: cachedSub, action: selectSub)
                    .id("\(cachedSub.uuid ?? "")-fav")
                    .onAppear {
                      UIApplication.shared.shortcutItems?.append(UIApplicationShortcutItem(type: "subFav", localizedTitle: cachedSub.display_name ?? "Test", localizedSubtitle: "", icon: UIApplicationShortcutIcon(type: .love), userInfo: ["name": "sub" as NSSecureCoding]))
                    }
                }
                .onDelete(perform: deleteFromFavorites)
              }
            }

            if appearanceDefSettings.disableAlphabetLettersSectionsInSubsList {
              Section("Subs") {
                let subs = Array(subreddits.filter(\.user_is_subscriber).sorted(by: { x, y in (x.display_name?.lowercased() ?? "a") < (y.display_name?.lowercased() ?? "a") }).enumerated())
                ForEach(subs, id: \.self.element) { _, cachedSub in
                  let sub = Subreddit(data: SubredditData(entity: cachedSub))
                  SubItem(isActive: Router.NavDest.reddit(.subFeed(sub)) == firstDestination, sub: sub, cachedSub: cachedSub, action: selectSub)
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
                      let sub = Subreddit(data: SubredditData(entity: cachedSub))
                      SubItem(isActive: Router.NavDest.reddit(.subFeed(sub)) == firstDestination, sub: sub, cachedSub: cachedSub, action: selectSub)
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
        .themedListSection(disable: usesWindowBackground)
      }
      .environment(\.isInSidebar, true)
      .themedListBG(selectedTheme.lists.bg, disable: usesWindowBackground)
      .background {
        if usesWindowBackground {
          Color(uiColor: .systemBackground).ignoresSafeArea()
        }
      }
      .scrollIndicators(.hidden)
      .listStyle(.sidebar)
      .scrollDismissesKeyboard(.immediately)
      .loader(!loaded && subreddits.isEmpty)
      .subsSearchAndEdit($searchText)
      .overlay(alignment: .trailing) {
        // Without the sidebar's own shade, a hairline marks where the posts start.
        if usesWindowBackground {
          Color(uiColor: .separator).frame(width: 1).ignoresSafeArea()
        }
      }
      .overlay(
        AlphabetJumper(letters: sections.keys.sorted(), proxy: proxy),
        alignment: .trailing,
      )
      .refreshable {
        Task(priority: .utility) {
          await updatePostsInBox(RedditAPI.shared, force: true)
        }
        Task(priority: .utility) {
          _ = await RedditAPI.shared.fetchMyMultis()
        }
        _ = await RedditAPI.shared.fetchSubsAndSyncCoreData()
      }
      .navigationTitle("Subs")
    }
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
  func subsSearchAndEdit(_ searchText: Binding<String>) -> some View {
    #if targetEnvironment(macCatalyst)
      safeAreaInset(edge: .top, spacing: 0) { MacSubsHeader(searchText: searchText) }
        .toolbar(.hidden, for: .navigationBar)
    #else
      searchable(text: searchText, prompt: "Search my subreddits")
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

    var body: some View {
      HStack(spacing: 10) {
        HStack(spacing: 6) {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(.secondary)
          TextField("Search my subreddits", text: $searchText)
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
