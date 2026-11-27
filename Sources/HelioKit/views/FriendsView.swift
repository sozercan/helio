import Defaults
import SwiftUI

@MainActor
@Observable
final class FriendsListModel {
  enum State: Equatable {
    case loading
    case loaded
    case error
  }

  private(set) var friends: [RedditFriend] = []
  private(set) var state: State = .loading
  @ObservationIgnored private var requestID: UUID?
  private let fetchFriends: @Sendable (RedditCredential?) async -> [RedditFriend]?
  private let removeFriendRequest: @Sendable (String, RedditCredential?) async -> Bool
  private let currentAccount: @MainActor () -> RedditCredential?

  init(
    currentAccount: @escaping @MainActor () -> RedditCredential? = { RedditCredentialsManager.shared.selectedCredential },
    fetchFriends: @escaping @Sendable (RedditCredential?) async -> [RedditFriend]? = { await RedditAPI.shared.fetchFriends(altCredential: $0) },
    removeFriendRequest: @escaping @Sendable (String, RedditCredential?) async -> Bool = { await RedditAPI.shared.setFriend($0, isFriend: false, altCredential: $1) },
  ) {
    self.currentAccount = currentAccount
    self.fetchFriends = fetchFriends
    self.removeFriendRequest = removeFriendRequest
  }

  func load(clearExisting: Bool = false) async {
    guard !Task.isCancelled else { return }
    guard let account = currentAccount(), let authorization = account.authorizationID else {
      friends = []
      state = .error
      return
    }
    let id = UUID()
    requestID = id
    if clearExisting || friends.isEmpty {
      if clearExisting {
        friends = []
      }
      state = .loading
    }
    let loaded = await fetchFriends(account)
    guard requestID == id, !Task.isCancelled,
          currentAccount()?.authorizationID == authorization else { return }
    if let loaded {
      friends = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
      state = .loaded
    } else {
      state = .error
    }
  }

  func remove(_ friend: RedditFriend) async -> Bool {
    guard let account = currentAccount(), let authorization = account.authorizationID else { return false }
    let removed = await removeFriendRequest(friend.name, account)
    guard removed, currentAccount()?.authorizationID == authorization else { return false }
    friends.removeAll { $0.id == friend.id }
    return true
  }
}

struct FriendsView: View {
  @State private var model = FriendsListModel()
  @State private var removingIDs: Set<String> = []
  @Environment(\.useTheme) private var selectedTheme
  @Environment(\.navColumn) private var navColumn
  @Default(.GeneralDefSettings) private var generalDefSettings

  private var selectedAuthorization: RedditCredential.AuthorizationID? {
    RedditCredentialsManager.shared.selectedCredential(id: generalDefSettings.redditCredentialSelectedID)?.authorizationID
  }

  var body: some View {
    List {
      switch model.state {
      case .loading:
        ProgressView()
          .frame(maxWidth: .infinity, minHeight: 200)
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
      case .error:
        ContentUnavailableView {
          Label("Unable to load friends", systemImage: "person.2.slash")
        } actions: {
          Button("Retry") {
            Task { await model.load() }
          }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
      case .loaded:
        if model.friends.isEmpty {
          ContentUnavailableView(
            "No Friends Yet",
            systemImage: "person.2",
            description: Text("Add someone from their profile to see them here."),
          )
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
        } else {
          Section {
            ForEach(model.friends) { friend in
              Button {
                Nav.to(.reddit(.user(User(id: friend.name))), from: navColumn)
              } label: {
                HStack(spacing: 12) {
                  VStack(alignment: .leading, spacing: 2) {
                    Text("u/\(friend.name)")
                      .fontSize(16, .semibold)
                      .foregroundStyle(selectedTheme.postLinks.theme.titleText.color())
                    if let date = friend.date {
                      Text("Friends since \(Date(timeIntervalSince1970: date).toFormat("MMM dd, yyyy"))")
                        .fontSize(13)
                        .foregroundStyle(selectedTheme.postLinks.theme.badge.statsText.color())
                    }
                    if let note = friend.note, !note.isEmpty {
                      Text(note)
                        .fontSize(13)
                        .foregroundStyle(selectedTheme.postLinks.theme.badge.statsText.color())
                        .lineLimit(2)
                    }
                  }
                  Spacer()
                  if removingIDs.contains(friend.id) {
                    ProgressView()
                  } else {
                    Image(systemName: "chevron.right")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(.tertiary)
                  }
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button("Remove", systemImage: "person.badge.minus", role: .destructive) {
                  Task {
                    removingIDs.insert(friend.id)
                    _ = await model.remove(friend)
                    removingIDs.remove(friend.id)
                  }
                }
              }
            }
          }
          .themedListSection()
        }
      }
    }
    .themedListBG(selectedTheme.lists.bg)
    .navigationTitle("Friends")
    .navigationBarTitleDisplayMode(.inline)
    .refreshable {
      await model.load()
    }
    .task {
      await model.load()
    }
    .onChange(of: selectedAuthorization) { _, _ in
      Task { await model.load(clearExisting: true) }
    }
  }
}
