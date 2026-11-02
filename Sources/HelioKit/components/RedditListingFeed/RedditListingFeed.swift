//
//  RedditListingFeed.swift
//  Helio
//
//  Created by Igor Marcossi on 23/01/24.
//

import Defaults
import SwiftData
import SwiftUI

struct RedditListingFeed<Header: View, Footer: View, S: Sorting>: View {
  private var showSubInPosts: Bool
  private var title: String
  private var theme: ThemeBG
  //  private var fetch: (_ force: Bool, _ lastElementId: String?, _ searchQuery: String?) async -> [RedditEntityType]?
  private var header: () -> Header
  private var footer: () -> Footer
  private var subreddit: Subreddit?
  private var disableSearch: Bool
  var forceRefresh: Binding<Bool>?
  @Default(.SubredditFeedDefSettings) private var subredditFeedDefSettings
  @Default(.GeneralDefSettings) private var generalDefSettings

  private var selectedAuthorization: RedditCredential.AuthorizationID? {
    RedditCredentialsManager.shared.selectedCredential(id: generalDefSettings.redditCredentialSelectedID)?.authorizationID
  }

  init(feedId: String, showSubInPosts: Bool = false, title: String, theme: ThemeBG, fetch: @escaping FeedItemsManager<S>.ItemsFetchFn, @ViewBuilder header: @escaping () -> Header = { EmptyView() }, @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }, initialSorting: S? = nil, disableSearch: Bool = true, subreddit: Subreddit? = nil, forceRefresh: Binding<Bool>? = nil, hideReadPosts: Bool = false) where S == SubListingSortOption {
    self.showSubInPosts = showSubInPosts
    self.title = title
    self.theme = theme
    self.header = header
    self.footer = footer
    self.subreddit = subreddit
    self.disableSearch = disableSearch
    self.forceRefresh = forceRefresh // Assign the optional forceRefresh Binding
    self._itemsManager = .init(initialValue: FeedItemsManager(sorting: initialSorting, hideReadPosts: hideReadPosts, fetchFn: fetch))
    self._filters = FetchRequest<CachedFilter>(sortDescriptors: [NSSortDescriptor(key: "text", ascending: true)], predicate: NSPredicate(format: "subID == %@", (subreddit?.data?.display_name ?? feedId) as CVarArg), animation: .default)
  }

  @FetchRequest private var filters: FetchedResults<CachedFilter>

  @SilentState private var fetchedFilters: Bool = false

  @State private var itemsManager: FeedItemsManager<S>
  /// The search field's state, which the menu bar's Find sets.
  @State private var searchPresented = false
  /// Find focuses the field even while it's presented, after its keyboard was dismissed.
  @FocusState private var searchFocused: Bool

  @Environment(\.useTheme) private var selectedTheme
  @Environment(\.contentWidth) private var contentWidth
  @Environment(\.navColumn) private var navColumn

  @Default(.PostLinkDefSettings) private var postLinkDefSettings
  @Default(.SubredditFeedDefSettings) private var feedDefSettings

  func refetch(clearItems: Bool = false) async {
    //    if let subreddit, !feedsAndSuch.contains(subreddit.id) {
    //      Task {
    //        withAnimation { itemsManager.loadingPinned = true }
    //        if let pinnedPosts = await subreddit.fetchPinnedPosts() {
    //          itemsManager.pinnedPosts = pinnedPosts
    //        }
    //        withAnimation { itemsManager.loadingPinned = false }
    //      }
    //    }

    await itemsManager.reload(clearItems: clearItems)
    await fetchFiltersIfNeeded()
  }

  private func fetchFiltersIfNeeded() async {
    guard let subreddit, !fetchedFilters else { return }
    fetchedFilters = true
    await subreddit.fetchAndCacheFlairs()
  }

  var body: some View {
    let shallowCachedFilters = filters.map { $0.getShallow() }
    // Read once per update: each read of a setting decodes it, and rows are built as they scroll in.
    let compactPerSubreddit = feedDefSettings.compactPerSubreddit
    let postLinkSettings = postLinkDefSettings
    let isThereDivider = selectedTheme.postLinks.divider.style != .no
    let paddingH = selectedTheme.postLinks.theme.outerHPadding
    let paddingV = selectedTheme.postLinks.spacing / (isThereDivider ? 4 : 2)
    GeometryReader { geo in
      List {
        header()

        //        getPinnedSection()

        Group {
          switch itemsManager.displayMode {
          case .loading:
            Section {
              ProgressView()
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
                .padding(.bottom, 32)
                .id("initial-loading-indicator")
            }
          case .empty:
            Text("Nothing around here :(")
              .frame(maxWidth: .infinity)
          case .error, .endOfFeed, .items, .onlyReadPosts:
            Section {
              ForEach(itemsManager.entities) { el in
                Group {
                  switch el {
                  case let .post(post):
                    if let helioData = post.helioData, let sub = helioData.subreddit ?? subreddit {
                      PostLink(id: post.id, theme: selectedTheme.postLinks, showSub: showSubInPosts, compactPerSubreddit: compactPerSubreddit[sub.settingsKey], contentWidth: contentWidth, defSettings: postLinkSettings)
                        .environment(\.contextPost, post)
                        .environment(\.contextSubreddit, sub)
                        .environment(\.contextPostHelioData, helioData)
                        .listRowInsets(EdgeInsets(top: paddingV, leading: paddingH, bottom: paddingV, trailing: paddingH))

                      if isThereDivider {
                        // Compact rows get Apollo's inset hairline instead of the thick band.
                        let compact = compactPerSubreddit[sub.settingsKey] ?? postLinkSettings.compactMode.enabled
                        Group {
                          if compact, paddingH == 0 {
                            selectedTheme.lists.dividersColors()
                              .frame(height: 0.5)
                              .padding(.leading, selectedTheme.postLinks.theme.innerPadding.horizontal)
                              .background(selectedTheme.postLinks.theme.bg.color())
                          } else {
                            NiceDivider(divider: selectedTheme.postLinks.divider)
                          }
                        }
                        .id("\(post.id)-divider")
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                      }
                    }
                  case let .subreddit(sub):
                    SubredditLink(sub: sub)
                      .listRowInsets(EdgeInsets())
                  case .multi: EmptyView()
                  case let .comment(comment):
                    VStack(spacing: 8) {
                      ShortCommentPostLink(comment: comment)
                        .padding(.horizontal, 12)
                      if let commentHelioData = comment.helioData {
                        CommentLink(showReplies: false, comment: comment, commentHelioData: commentHelioData, children: comment.childrenHelio)
                      }
                    }
                    .padding(.vertical, 12)
                    .background(PostLinkBG(theme: selectedTheme.postLinks.theme, stickied: false, secondary: false))
                    .mask(RR(selectedTheme.postLinks.theme.cornerRadius, Color.black))
                    .allowsHitTesting(false)
                    .contentShape(Rectangle())
                    .onTapGesture {
                      if let data = comment.data, let link_id = data.link_id, let subID = data.subreddit {
                        // `link_id` is the post's fullname (t3_…); posts are made from the bare id, as
                        // the feed's are, so the open post matches its row there.
                        let postID = link_id.hasPrefix("t3_") ? String(link_id.dropFirst(3)) : link_id
                        Nav.to(.reddit(.postHighlighted(Post(id: postID, subID: subID), comment.id)), from: navColumn)
                      }
                    }
                    .listRowInsets(EdgeInsets(top: paddingV, leading: paddingH, bottom: paddingV, trailing: paddingH))
                  case let .user(user):
                    UserLink(user: user)
                      .listRowInsets(EdgeInsets())
                  case let .message(message):
                    // Flat, full-width rows with hairlines between them, like comments.
                    MessageLink(message: message)
                      .listRowInsets(EdgeInsets())
                  }
                }
                .onAppear { itemsManager.elementAppeared(entity: el) }
                .onDisappear { itemsManager.elementDisappeared(entity: el) }
              }
            }

            if itemsManager.displayMode == .endOfFeed {
              Section {
                EndOfFeedView()
              }
            }

            if itemsManager.displayMode == .onlyReadPosts {
              Section {
                VStack {
                  Text("Only posts you've read so far")

                  Button("Load more", systemImage: "arrow.down") {
                    Task { await itemsManager.loadMore() }
                  }
                  .buttonStyle(.actionSecondary)
                }
                .frame(maxWidth: .infinity)
                .compositingGroup()
                .opacity(0.5)
                .id("only-read-load-more")
              }
            }

            if itemsManager.displayMode == .error {
              Section {
                VStack {
                  if let limitedUntil = RedditRateLimit.shared.limitedUntil(account: RedditAPI.accountID(nil), authorization: RedditAPI.accountAuthorization(nil)) {
                    Text(RedditRateLimit.retryText(until: limitedUntil))
                      .multilineTextAlignment(.center)
                  } else {
                    Text("There was an error")
                  }

                  Button("Manually reload", systemImage: "arrow.clockwise") {
                    Task { await itemsManager.retry() }
                  }
                  .buttonStyle(.actionSecondary)
                }
                .frame(maxWidth: .infinity)
                .compositingGroup()
                .opacity(0.5)
                .id("error-load-more-manual")
              }
            }
            //          default: EmptyView()
          }

          if itemsManager.isLoadingMore {
            Section {
              ProgressView()
                .frame(maxWidth: .infinity, minHeight: 150)
                .id("loading-more-indicator")
            }
          }
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)

        footer()
      }
      .themedListBG(theme)
      // In the toolbar (the default in a split view's detail on iOS 26+), closing search
      // re-focuses it as soon as the dismiss animation ends.
      .if(!disableSearch) { $0.searchable(text: $itemsManager.searchQuery.value, isPresented: $searchPresented, placement: .navigationBarDrawer(displayMode: .automatic)).searchFocused($searchFocused) }
      .touchScrollIndicators(.never)
      .listStyle(.plain)
      .navigationTitle(title)
      .environment(\.defaultMinListRowHeight, 1)
      .toolbar {
        // Sort and the feed's options share a glass group; the subreddit's icon is its own.
        if itemsManager.sorting != nil {
          ToolbarItem(placement: .topBarTrailing) {
            FeedSortMenu(sorting: $itemsManager.sorting)
          }
        }
        if let subreddit {
          ToolbarItem(placement: .topBarTrailing) {
            FeedOptionsMenu(subId: subreddit.settingsKey, filters: shallowCachedFilters, selectedFilter: $itemsManager.selectedFilter)
          }
        }
        if let sub = subreddit, let data = sub.data {
          ToolbarSpacer(.fixed, placement: .topBarTrailing)
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              Nav.to(.reddit(.subInfo(sub)), from: navColumn)
            } label: {
              SubredditIcon(subredditIconKit: data.subredditIconKit)
            }
            .accessibilityLabel("About r/\(data.display_name ?? sub.id)")
          }
        }
      }
      .relayoutPosts({ itemsManager.entities.compactMap {
        if case let .post(post) = $0 {
          post
        } else {
          nil
        }
      } }, contentWidth: contentWidth, theme: selectedTheme)
      // A feed opened by name gains its fullname with its details, and with it the compact
      // setting kept under it: lay its posts out again for it.
      .onChange(of: subreddit?.settingsKey) {
        withAnimation {
          for case let .post(post) in itemsManager.entities {
            post.relayout(contentWidth: contentWidth, theme: selectedTheme)
          }
        }
      }
      //    .onChange(of: itemsManager.selectedFilter) { searchEnabled = $1?.type != .custom }
      .refreshable { await refetch() }
      .feedCommandTarget(CommandTargets.Target(
        kind: .feed,
        column: navColumn,
        refresh: { Task { await refetch() } },
        focusSearch: disableSearch ? nil : {
          searchPresented = true
          searchFocused = true
        },
        posts: { itemsManager.entities.compactMap {
          if case let .post(post) = $0 {
            post
          } else {
            nil
          }
        } },
        canLoadMore: { itemsManager.canLoadMore },
        loadMore: { await itemsManager.loadMore() },
      ))
      .onChange(of: selectedAuthorization) { _, _ in
        Task { await refetch(clearItems: true) }
      }
      .onChange(of: subredditFeedDefSettings.chunkLoadSize) { itemsManager.chunkSize = $1 }
      .onChange(of: forceRefresh?.wrappedValue) { newValue in
        if newValue == true {
          Task {
            await refetch()
            forceRefresh?.wrappedValue = false // Reset
          }
        }
      }
      .onAppear {
        // The manager owns the initial request, independent of navigation task cancellation.
        Task {
          await itemsManager.loadIfNeeded()
          await fetchFiltersIfNeeded()
        }
      }
      .onChange(of: [itemsManager.searchQuery.debounced, itemsManager.selectedFilter?.text, itemsManager.selectedFilter?.type.rawValue, itemsManager.sorting?.meta.apiValue]) {
        Task { await refetch() }
      }
    }
  }
}

/// The feed's sort, with a checkmark on the current one. Top's time ranges are a submenu.
private struct FeedSortMenu<S: Sorting>: View {
  @Binding var sorting: S?

  var body: some View {
    Menu {
      Picker("Sort", selection: $sorting) {
        ForEach(Array(S.allCases).filter { $0.meta.children == nil }, id: \.self) { opt in
          Label(opt.meta.label, systemImage: opt.meta.icon)
            .tag(Optional(opt))
        }
      }
      ForEach(Array(S.allCases).filter { $0.meta.children != nil }, id: \.self) { opt in
        Picker(selection: $sorting) {
          ForEach(opt.meta.children ?? [], id: \.self.meta.apiValue) { child in
            if let val = child.valueWithParent as? S {
              Label(child.meta.label, systemImage: child.meta.icon)
                .tag(Optional(val))
            }
          }
        } label: {
          Label(opt.meta.label, systemImage: opt.meta.icon)
        }
        .pickerStyle(.menu)
      }
    } label: {
      Label("Sort", systemImage: sorting?.meta.icon ?? "arrow.up.arrow.down")
    }
  }
}

/// The feed's flair filter and its compact-posts switch. The icon fills while a filter is on.
private struct FeedOptionsMenu: View {
  var subId: String
  var filters: [ShallowCachedFilter]
  /// A filter's identity in the picker: its kind and text.
  static func key(_ filter: ShallowCachedFilter) -> String {
    filter.pickerKey
  }

  @Binding var selectedFilter: ShallowCachedFilter?

  @Default(.SubredditFeedDefSettings) private var subredditFeedDefSettings
  @Default(.PostLinkDefSettings) private var postLinkDefSettings

  private var compact: Binding<Bool> {
    Binding {
      subredditFeedDefSettings.compactPerSubreddit[subId] ?? postLinkDefSettings.compactMode.enabled
    } set: {
      subredditFeedDefSettings.compactPerSubreddit[subId] = $0
    }
  }

  var body: some View {
    let flairs = filters.filter { $0.type == .flair }
    let custom = filters.filter { $0.type == .custom }
    Menu {
      Toggle("Compact posts", systemImage: "rectangle.compress.vertical", isOn: compact)
      // Also while a filter is on, so it can be cleared even after a refresh dropped its flair.
      if !flairs.isEmpty || !custom.isEmpty || selectedFilter != nil {
        // Tagged by the filter's kind and text, not the whole filter: a background refresh can
        // change a flair's colors, which would leave the active one unchecked. Flairs with the
        // same text in different colors show once.
        var seen = Set<String>()
        let options = (flairs + custom).filter { seen.insert(Self.key($0)).inserted }
        Picker("Flair", selection: Binding(
          get: { selectedFilter.map(Self.key) },
          set: { key in selectedFilter = key.flatMap { key in options.first { Self.key($0) == key } } },
        )) {
          Label("All posts", systemImage: "square.stack")
            .tag(String?.none)
          ForEach(options, id: \.self.pickerKey) { filter in
            Text(filter.text)
              .tag(Optional(Self.key(filter)))
          }
        }
        .pickerStyle(.inline)
      }
    } label: {
      Label("Filter", systemImage: selectedFilter == nil ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
    }
    .accessibilityLabel("Filter and view options")
    .accessibilityValue(selectedFilter.map { "Showing \($0.text)" } ?? "")
  }
}

extension ShallowCachedFilter {
  /// The filter's identity in menus: its kind and text, not its colors, which a refresh can
  /// change while it's selected.
  var pickerKey: String {
    "\(type.rawValue)|\(text)"
  }
}
