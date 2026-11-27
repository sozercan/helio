import Defaults
import NukeUI
import SwiftUI

struct UserView: View {
  var user: User
  var isOwnProfile = false
  @Default(.SubredditFeedDefSettings) private var subFeedSettings
  @Default(.GeneralDefSettings) private var generalDefSettings
  @Environment(\.useTheme) private var selectedTheme
  @Environment(\.navColumn) private var navColumn

  @State private var selectedSection: UserListingSection = .overview
  @State private var forceRefresh = false
  @State private var updatingFriend = false
  @State private var refreshingUser = false
  @State private var userFetchID = UUID()

  private var selectedAuthorization: RedditCredential.AuthorizationID? {
    RedditCredentialsManager.shared.selectedCredential(id: generalDefSettings.redditCredentialSelectedID)?.authorizationID
  }

  private var isCurrentUser: Bool {
    if isOwnProfile {
      return true
    }
    guard let selectedAuthorization,
          let currentAccount = RedditCredentialsManager.shared.selectedCredential(id: generalDefSettings.redditCredentialSelectedID),
          currentAccount.authorizationID == selectedAuthorization
    else { return false }
    let currentName = currentAccount.userName ?? RedditCredentialsManager.profile.user?.data?.name
    guard let currentName,
          let profileName = user.data?.name ?? (user.id.isEmpty ? nil : user.id)
    else { return false }
    return currentName.caseInsensitiveCompare(profileName) == .orderedSame
  }

  private var availableSections: [UserListingSection] {
    isCurrentUser ? UserListingSection.ownSections : UserListingSection.publicSections
  }

  func fetcher(_ after: String?, _ sorting: SubListingSortOption?, _ searchQuery: String?, _ flair: String?, _ context: FeedItemsManager<SubListingSortOption>.FetchContext) async -> ([RedditEntityType]?, String?)? {
    if let overviewDataResult = await user.refetchOverview(section: selectedSection, after, contentWidth: context.contentWidth, limit: context.limit, altCredential: context.credential), let overviewData = overviewDataResult.0 {
      Task { await user.redditAPI.updateOverviewSubjectsWithAvatar(subjects: overviewData, avatarSize: selectedTheme.postLinks.theme.badge.avatar.size) }

      let newData: [RedditEntityType]? = overviewData.compactMap {
        if case let .first(post) = $0 {
          return .post(post)
        } else if case let .second(comment) = $0 {
          return .comment(comment)
        }
        return nil
      }

      return (newData, overviewDataResult.1)
    }
    return nil
  }

  private func toggleSection(_ section: UserListingSection) {
    withAnimation(.easeInOut(duration: 0.2)) {
      selectedSection = selectedSection == section ? .overview : section
    }
  }

  private func toggleFriend() {
    guard !updatingFriend, !refreshingUser, let currentFriend = user.data?.is_friend else { return }
    let account = RedditCredentialsManager.shared.selectedCredential
    let authorization = account?.authorizationID
    updatingFriend = true
    Task {
      _ = await user.setFriend(!currentFriend, altCredential: account)
      if RedditCredentialsManager.shared.selectedCredential?.authorizationID == authorization {
        updatingFriend = false
      }
    }
  }

  private func reloadUserForCurrentAccount() async {
    let fetchID = UUID()
    userFetchID = fetchID
    let account = RedditCredentialsManager.shared.selectedCredential(id: generalDefSettings.redditCredentialSelectedID)
    let authorization = account?.authorizationID
    refreshingUser = true
    user.data?.is_friend = nil
    let userName = user.data?.name ?? user.id
    let fetched = await RedditAPI.shared.fetchUser(userName, altCredential: account)
    guard userFetchID == fetchID,
          !Task.isCancelled,
          selectedAuthorization == authorization
    else { return }
    if let fetched {
      user.data = fetched
    }
    refreshingUser = false
  }

  var body: some View {
    RedditListingFeed(feedId: user.fullname, showSubInPosts: true, title: "\(subFeedSettings.showPrefixOnFeedTitle ? "u/" : "")\(user.data?.name ?? "Loading...")", theme: selectedTheme.lists.bg, fetch: fetcher, header: {
      VStack(spacing: 16) {
        if let data = user.data {
          Group {
            ZStack {
              if let bannerImgFull = data.subreddit?.banner_img, !bannerImgFull.isEmpty, let bannerImg = URL(string: String(bannerImgFull.split(separator: "?")[0])) {
                URLImage(url: bannerImg)
                  .scaledToFill()
                  .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 160)
                  .mask(RR(16, Color.black))
              }
              if let iconFull = data.subreddit?.icon_img, iconFull != "", let icon = URL(string: String(iconFull.split(separator: "?")[0])) {
                URLImage(url: icon)
                  .scaledToFill()
                  .frame(width: 125, height: 125)
                  .mask(Circle())
                  .offset(y: data.subreddit?.banner_img == "" || data.subreddit?.banner_img == nil ? 0 : 80)
              }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, data.subreddit?.banner_img == "" || data.subreddit?.banner_img == nil ? 0 : 78)

            if let description = data.subreddit?.public_description, !description.isEmpty {
              Text(description.md())
                .fontSize(15)
                .multilineTextAlignment(.center)
            }

            if !isCurrentUser, !refreshingUser, let isFriend = data.is_friend {
              Button(action: toggleFriend) {
                HStack(spacing: 6) {
                  if updatingFriend {
                    ProgressView()
                      .controlSize(.small)
                  } else {
                    Image(systemName: isFriend ? "person.badge.minus" : "person.badge.plus")
                  }
                  Text(isFriend ? "Remove Friend" : "Add Friend")
                }
                .fontSize(15, .semibold)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .foregroundStyle(isFriend ? selectedTheme.postLinks.theme.titleText.color() : Color.white)
                .background(isFriend ? Color.secondary.opacity(0.2) : selectedTheme.general.accentColor(), in: Capsule())
              }
              .buttonStyle(.plain)
              .disabled(updatingFriend)
            }

            VStack {
              let accentColor = selectedTheme.general.accentColor()
              HStack {
                if let postKarma = data.link_karma {
                  DataBlock(
                    icon: "highlighter",
                    label: "Post karma",
                    value: "\(formatBigNumber(postKarma))",
                    iconColor: accentColor,
                    labelColor: selectedTheme.postLinks.theme.badge.statsText.color(),
                    valueColor: selectedTheme.postLinks.theme.titleText.color(),
                  )
                  .transition(.opacity)
                  .onTapGesture {
                    toggleSection(.submitted)
                  }
                  .overlay(selectedSection == .submitted ?
                    accentColor.opacity(0.2)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .allowsHitTesting(false)
                    : nil)
                }

                if let commentKarma = data.comment_karma {
                  DataBlock(
                    icon: "checkmark.message.fill",
                    label: "Comment karma",
                    value: "\(formatBigNumber(commentKarma))",
                    iconColor: accentColor,
                    labelColor: selectedTheme.postLinks.theme.badge.statsText.color(),
                    valueColor: selectedTheme.postLinks.theme.titleText.color(),
                  )
                  .transition(.opacity)
                  .onTapGesture {
                    toggleSection(.comments)
                  }
                  .overlay(selectedSection == .comments ?
                    accentColor.opacity(0.2)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .allowsHitTesting(false)
                    : nil)
                }
              }
              if let created = data.created {
                DataBlock(
                  icon: "star.fill",
                  label: "User since",
                  value: "\(Date(timeIntervalSince1970: TimeInterval(created)).toFormat("MMM dd, yyyy"))",
                  iconColor: accentColor,
                  labelColor: selectedTheme.postLinks.theme.badge.statsText.color(),
                  valueColor: selectedTheme.postLinks.theme.titleText.color(),
                )
                .transition(.opacity)
              }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .transition(.opacity)
          }

          if isCurrentUser {
            Button {
              Nav.to(.reddit(.friends), from: navColumn)
            } label: {
              HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                  .fontSize(18, .semibold)
                  .foregroundStyle(selectedTheme.general.accentColor())
                Text("Friends")
                  .fontSize(16, .semibold)
                  .foregroundStyle(selectedTheme.postLinks.theme.titleText.color())
                Spacer()
                Image(systemName: "chevron.right")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.tertiary)
              }
              .padding(.horizontal, 16)
              .padding(.vertical, 12)
              .themedListRowLikeBG()
              .mask(RR(16, Color.black))
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
          }

          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              ForEach(availableSections) { section in
                let isSelected = selectedSection == section
                Button {
                  withAnimation(.easeInOut(duration: 0.2)) {
                    selectedSection = section
                  }
                } label: {
                  Label(section.label, systemImage: section.systemImage)
                    .fontSize(14, .semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(isSelected ? Color.white : selectedTheme.postLinks.theme.titleText.color())
                    .background(isSelected ? selectedTheme.general.accentColor() : Color.secondary.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
              }
            }
            .padding(.horizontal, 8)
          }

          Text(selectedSection.heading)
            .fontSize(20, .bold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
      }
      .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
      .listRowSeparator(.hidden)
      .listRowBackground(Color.clear)
      .transition(.opacity)
    }, disableSearch: true, forceRefresh: $forceRefresh)
      .navigationBarTitleDisplayMode(.inline)
      .task {
        if user.data == nil {
          await reloadUserForCurrentAccount()
        }
      }
      .onChange(of: selectedSection) { _, _ in
        forceRefresh = true
      }
      .onChange(of: selectedAuthorization) { _, _ in
        updatingFriend = false
        if !isCurrentUser, selectedSection.isPrivate {
          selectedSection = .overview
        }
        if !isOwnProfile {
          Task { await reloadUserForCurrentAccount() }
        }
      }
  }
}
