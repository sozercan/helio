//
//  Search.swift
//  winston
//
//  Created by Igor Marcossi on 24/06/23.
//

import SwiftUI
import NukeUI
import Defaults

enum SearchType: String, Codable {
  case subreddit = "Subreddit"
  case user = "User"
  case post = "Post"
}

struct SearchOption: View {
  var activateSearchType: ()->()
  var active: Bool
  var searchType: SearchType
  var body: some View {
    Text(searchType.rawValue)
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(Capsule(style: .continuous).fill(active ? Color.accentColor : .secondary.opacity(0.15)))
      .foregroundColor(active ? .white : .primary)
      .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke((active ? Color.white : .primary).opacity(0.01), lineWidth: 1))
      .contentShape(Capsule())
      .onTapGesture {
        withAnimation(.interactiveSpring()) {
          activateSearchType()
        }
      }
      .shrinkOnTap()
  }
}

enum SearchTypeArr {
  case subreddit([Subreddit])
  case user([User])
  case post([Post])
}

struct Search: View {
  @State var router: Router
  
  @State private var searchType: SearchType = .subreddit
  @State private var resultsSubs: [Subreddit] = []
  @State private var resultsUsers: [User] = []
  @State private var resultPosts: [Post] = []
  @State private var loading = false
  @State private var hideSpinner = false
  @State var searchQuery = Debouncer("", delay: 0.25)
  
  @State private var dummyAllSub: Subreddit? = nil
  @State private var searchViewLoaded: Bool = false
  
  @Default(.PostLinkDefSettings) private var postLinkDefSettings
  @Default(.searchHistory) private var searchHistory
  @Environment(\.useTheme) private var theme
  @Environment(\.contentWidth) private var contentWidth
  
  init(router: Router) {
    self._router = .init(initialValue: router)
  }
  
  func fetch() {
    if searchQuery.value == "" { return }
    withAnimation {
      loading = true
    }
    switch searchType {
    case .subreddit:
      resultsSubs.removeAll()
      Task(priority: .background) {
        let subs = await RedditAPI.shared.searchSubreddits(searchQuery.value)?.map({ Subreddit(data: $0) })
        await MainActor.run {
          withAnimation {
            resultsSubs = subs ?? []
            loading = false
            
            hideSpinner = resultsSubs.isEmpty
          }
        }
      }
    case .user:
      resultsUsers.removeAll()
      Task(priority: .background) {
        let users = await RedditAPI.shared.searchUsers(searchQuery.value)?.map({ User(data: $0) })
        await MainActor.run {
          withAnimation {
            resultsUsers = users ?? []
            loading = false
            
            hideSpinner = resultsUsers.isEmpty
          }
        }
      }
    case .post:
      resultPosts.removeAll()
      Task(priority: .background) {
        let newPosts = await dummyAllSub?.fetchPosts(searchText: searchQuery.value)?.0 ?? []
        let actualNewPosts = newPosts.compactMap {
          if case .post(let post) = $0 {
            return post
          }
          return nil
        }
        await MainActor.run {
          withAnimation {
            resultPosts = actualNewPosts
            loading = false
            
            hideSpinner = resultPosts.isEmpty
          }
        }
      }
    }
  }
  
  func rememberSearch() {
    searchHistory = SearchHistory.record(searchQuery.value, type: searchType, in: searchHistory)
  }
  
  func search(_ item: SearchHistoryItem) {
    let unchanged = searchType == item.type && searchQuery.debounced == item.query
    searchType = item.type
    // Skips the debounce, so the change below fetches once, now.
    searchQuery.setNow(item.query)
    rememberSearch()
    if unchanged { fetch() }
    UIApplication.shared.dismissKeyboard()
  }
  
  func historyRow(_ item: SearchHistoryItem) -> some View {
    HStack(spacing: 12) {
      Image(systemName: item.type.historyIcon)
        .foregroundStyle(.secondary)
        .frame(width: 24)
      Text(item.query)
        .lineLimit(1)
      Spacer()
      Button {
        if let i = searchHistory.firstIndex(of: item) { searchHistory[i].isFavorite.toggle() }
      } label: {
        Image(systemName: item.isFavorite ? "star.fill" : "star")
          .foregroundStyle(item.isFavorite ? Color.yellow : Color.secondary)
      }
      .buttonStyle(.plain)
    }
    .contentShape(Rectangle())
    .onTapGesture { search(item) }
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      Button(role: .destructive) {
        withAnimation { searchHistory.removeAll { $0.id == item.id } }
      } label: {
        Label("Delete", systemImage: "trash")
      }
    }
  }
  
  var body: some View {
    NavigationStack(path: $router.fullPath) {
      List {
        Group {
          Section {
            HStack {
              SearchOption(activateSearchType: { searchType = .subreddit }, active: searchType == SearchType.subreddit, searchType: .subreddit)
              SearchOption(activateSearchType: { searchType = .user }, active: searchType == SearchType.user, searchType: .user)
              SearchOption(activateSearchType: { searchType = .post }, active: searchType == SearchType.post, searchType: .post)
            }
            .id("options")
          }
          
          if searchQuery.value.isEmpty {
            let favorites = searchHistory.filter(\.isFavorite)
            let recents = searchHistory.filter { !$0.isFavorite }
            if !favorites.isEmpty {
              Section("Favorite searches") {
                ForEach(favorites) { historyRow($0) }
              }
            }
            if !recents.isEmpty {
              Section {
                ForEach(recents) { historyRow($0) }
              } header: {
                HStack {
                  Text("Recent searches")
                  Spacer()
                  Button("Clear") {
                    withAnimation { searchHistory.removeAll { !$0.isFavorite } }
                  }
                  .font(.subheadline)
                }
              }
            }
          } else {
            let suggestions = SearchHistory.suggestions(for: searchQuery.value, in: searchHistory)
            if !suggestions.isEmpty {
              Section {
                ForEach(suggestions) { historyRow($0) }
              }
            }
          }
          
          Section {
            switch searchType {
            case .subreddit:
              ForEach(resultsSubs) { sub in
                SubredditLink(sub: sub)
                  .simultaneousGesture(TapGesture().onEnded { rememberSearch() })
              }
            case .user:
              ForEach(resultsUsers) { user in
                UserLink(user: user)
                  .simultaneousGesture(TapGesture().onEnded { rememberSearch() })
              }
            case .post:
              if let dummyAllSub = dummyAllSub {
                ForEach(resultPosts) { post in
                  if let winstonData = post.winstonData {
                    //                      SwipeRevolution(size: winstonData.postDimensions.size, actionsSet: postSwipeActions, entity: post) { controller in
                    PostLink(id: post.id, theme: theme.postLinks, showSub: true, compactPerSubreddit: nil, contentWidth: contentWidth, defSettings: postLinkDefSettings)
//                    .swipyRev(size: winstonData.postDimensions.size, actionsSet: postSwipeActions, entity: post)
                    //                      }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .simultaneousGesture(TapGesture().onEnded { rememberSearch() })
                    .animation(.default, value: resultPosts)
                    .environment(\.contextPost, post)
                    .environment(\.contextSubreddit, dummyAllSub)
                    .environment(\.contextPostWinstonData, winstonData)
                  }
                }
              }
            }
          }
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
      }
      .themedListBG(theme.lists.bg)
      .listStyle(.plain)
      .loader(loading, hideSpinner && !searchQuery.value.isEmpty)
      .attachViewControllerToRouter(tabID: .search)
      .injectInTabDestinations()
      .scrollDismissesKeyboard(.automatic)
      .searchable(text: $searchQuery.value, placement: .toolbar)
      .autocorrectionDisabled(true)
      .textInputAutocapitalization(.none)
      .refreshable { fetch() }
      .onSubmit(of: .search) {
        rememberSearch()
        fetch()
      }
      .navigationTitle("Search")
      // One handler, so changing the type and the query together fetches once.
      .onChange(of: [searchType.rawValue, searchQuery.debounced]) {
        if searchQuery.debounced == "" {
          resultsSubs = []
          resultsUsers = []
          resultPosts = []
        }
        fetch()
      }
      .onAppear() {
        if !searchViewLoaded {
          dummyAllSub = Subreddit(id: "all")
          searchViewLoaded = true
        }
      }
    }
//    .swipeAnywhere()
  }
}

private extension SearchType {
  var historyIcon: String {
    switch self {
    case .subreddit: "r.square"
    case .user: "person"
    case .post: "doc.text"
    }
  }
}
