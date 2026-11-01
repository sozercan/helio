import Defaults
import Foundation
import Observation
import Synchronization
import Testing
@testable import HelioKit

@MainActor
struct CredentialStoreMutationTests {
  private func credential(_ grant: String = "placeholder-refresh-token") -> RedditCredential {
    RedditCredential(apiAppID: "placeholder-client-id", apiAppSecret: "placeholder-client-secret", refreshToken: grant)
  }

  private func token(_ value: String = "placeholder-access-token") -> RedditCredential.AccessToken {
    .init(token: value, expiration: 3600, lastRefresh: Date(timeIntervalSince1970: 1000))
  }

  /// Never hold shared preference changes across a suspension or another test's actor turn.
  private func withSelection(_ id: UUID?, _ operation: @MainActor () throws -> Void) rethrows {
    let previousID = Defaults[.GeneralDefSettings].redditCredentialSelectedID
    defer { Defaults[.GeneralDefSettings].redditCredentialSelectedID = previousID }
    Defaults[.GeneralDefSettings].redditCredentialSelectedID = id
    try operation()
  }

  private func expectObservableMutation(_ manager: RedditCredentialsManager, _ operation: @MainActor () -> Void) {
    let changes = Mutex(0)
    withObservationTracking {
      _ = manager.credentials
    } onChange: {
      changes.withLock { $0 += 1 }
    }
    operation()
    #expect(changes.withLock { $0 } == 1)
  }

  @Test func saveRefreshDeleteAndWipeAreObservableBeforeReturning() throws {
    let account = credential()
    let other = credential("placeholder-other-grant")
    let authorization = try #require(account.authorizationID)
    var reloads = 0
    let manager = RedditCredentialsManager(credentials: [], reloadSelectedProfile: { reloads += 1 })

    withSelection(nil) {
      expectObservableMutation(manager) { manager.saveCred(account) }
      #expect(manager.credentials == [account])
      #expect(manager.selectedCredential == account)
      #expect(Defaults[.GeneralDefSettings].redditCredentialSelectedID == account.id)
      #expect(reloads == 1)

      expectObservableMutation(manager) { manager.updateAccessToken(token(), for: authorization) }
      #expect(manager.selectedCredential?.accessToken == token())
      #expect(reloads == 1)

      expectObservableMutation(manager) { manager.saveCred(other) }
      #expect(manager.credentials.count == 2)
      #expect(manager.selectedCredential?.id == account.id)
      #expect(reloads == 1)

      expectObservableMutation(manager) { manager.deleteCred(account) }
      #expect(manager.credentials == [other])
      #expect(manager.selectedCredential == other)
      #expect(reloads == 2)

      expectObservableMutation(manager) { manager.wipeAllCredentials() }
      #expect(manager.credentials.isEmpty)
      #expect(manager.selectedCredential == nil)
      #expect(reloads == 3)
    }
  }

  @Test func refreshMergesIntoAnAlreadySavedMetadataEdit() throws {
    let account = credential()
    let authorization = try #require(account.authorizationID)
    let manager = RedditCredentialsManager(credentials: [account])
    var edited = account
    edited.userName = "placeholder-edited-user"
    edited.userAgent = "placeholder-edited-agent"
    edited.profilePicture = "https://example.com/edited-avatar.png"

    withSelection(account.id) {
      manager.saveCred(edited, forceCreate: false)
      manager.updateAccessToken(token(), for: authorization)
      edited.accessToken = token()
      #expect(manager.credentials == [edited])
    }
  }

  @Test(arguments: [false, true]) func staleRefreshCannotMutateASameIDReplacement(rejected: Bool) throws {
    let account = credential()
    let authorization = try #require(account.authorizationID)
    let manager = RedditCredentialsManager(credentials: [account])
    var replacement = account
    replacement.refreshToken = "placeholder-replacement-grant"
    replacement.accessToken = token("placeholder-replacement-token")
    replacement.userName = "placeholder-replacement-user"

    withSelection(account.id) {
      manager.saveCred(replacement)
      manager.updateAccessToken(rejected ? nil : token("placeholder-stale-token"), for: authorization)
      #expect(manager.credentials == [replacement])
      #expect(!manager.containsAuthorization(authorization))
    }
  }

  @Test(arguments: [false, true]) func staleRefreshCannotRestoreADeletedOrWipedRecord(wipe: Bool) throws {
    let account = credential()
    let authorization = try #require(account.authorizationID)
    let manager = RedditCredentialsManager(credentials: [account])
    if wipe {
      manager.wipeAllCredentials()
    } else {
      manager.deleteCred(account)
    }
    manager.updateAccessToken(token(), for: authorization)
    manager.updateAccessToken(nil, for: authorization)
    #expect(manager.credentials.isEmpty)
    #expect(!manager.containsAuthorization(authorization))
  }

  @Test func delayedRefreshCannotRestoreAnOlderToken() throws {
    let account = credential()
    let authorization = try #require(account.authorizationID)
    let manager = RedditCredentialsManager(credentials: [account])
    let old = RedditCredential.AccessToken(token: "placeholder-rejected-token", expiration: 3600, lastRefresh: Date(timeIntervalSince1970: 1))
    let new = RedditCredential.AccessToken(token: "placeholder-new-token", expiration: 3600, lastRefresh: Date(timeIntervalSince1970: 2))
    manager.updateAccessToken(new, for: authorization)
    manager.updateAccessToken(old, for: authorization)
    #expect(manager.credentials[0].accessToken == new)
  }

  @Test func migratedUserNamesAreBackfilledOnlyForTheCapturedGrant() async throws {
    let account = credential()
    let manager = RedditCredentialsManager(credentials: [account])
    let profile = SelectedAccountProfile(currentAccount: { manager.selectedCredential }, fetch: { _ in try? user("placeholder-migrated-user") }, persistUserName: { manager.backfillUserName($0, for: $1) })
    await profile.refresh()
    #expect(manager.credentials[0].userName == "placeholder-migrated-user")
    #expect(profile.state == .ready)
    let authorization = try #require(account.authorizationID)
    manager.backfillUserName("placeholder-later-name", for: authorization)
    #expect(manager.credentials[0].userName == "placeholder-migrated-user")
    var replacement = account
    replacement.refreshToken = "placeholder-replacement-grant"
    manager.saveCred(replacement)
    manager.backfillUserName("placeholder-stale-name", for: authorization)
    #expect(manager.credentials[0].userName == nil)
  }

  @Test func updateOnlySaveDoesNotRecreateOrSelectARemovedRecord() {
    let account = credential()
    var reloads = 0
    let manager = RedditCredentialsManager(credentials: [], reloadSelectedProfile: { reloads += 1 })
    withSelection(nil) {
      manager.saveCred(account, forceCreate: false)
      #expect(manager.credentials.isEmpty)
      #expect(Defaults[.GeneralDefSettings].redditCredentialSelectedID == nil)
      #expect(reloads == 0)
    }
  }

  @Test func currentNonselectedGrantsStillAcceptRefreshAndRejection() throws {
    let selected = credential("placeholder-selected-grant")
    var other = credential("placeholder-other-grant")
    other.userName = "placeholder-other-user"
    let authorization = try #require(other.authorizationID)
    var reloads = 0
    let manager = RedditCredentialsManager(credentials: [selected, other], reloadSelectedProfile: { reloads += 1 })
    withSelection(selected.id) {
      manager.updateAccessToken(token(), for: authorization)
      #expect(manager.credentials[1].accessToken == token())
      #expect(manager.credentials[1].userName == other.userName)
      #expect(manager.containsAuthorization(authorization))
      #expect(manager.selectedCredential == selected)
      #expect(reloads == 0)

      manager.updateAccessToken(nil, for: authorization)
      #expect(manager.credentials[1].authorizationID == nil)
      #expect(manager.credentials[1].userName == nil)
      #expect(manager.selectedCredential == selected)
      #expect(reloads == 0)
    }
  }

  private func user(_ name: String) throws -> UserData {
    let data = try JSONSerialization.data(withJSONObject: ["id": name, "name": name])
    return try JSONDecoder().decode(UserData.self, from: data)
  }

  @MainActor
  private final class Fetch {
    private var responses: [CheckedContinuation<UserData?, Never>] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func call(_: RedditCredential) async -> UserData? {
      await withCheckedContinuation { continuation in
        responses.append(continuation)
        let ready = waiters.filter { responses.count >= $0.0 }
        waiters.removeAll { responses.count >= $0.0 }
        ready.forEach { $0.1.resume() }
      }
    }

    func waitForCalls(_ count: Int) async {
      if responses.count >= count {
        return
      }
      await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func complete(_ index: Int, with data: UserData?) {
      responses[index].resume(returning: data)
    }
  }

  @MainActor
  private final class ProfileStore {
    let fetch: Fetch
    private(set) var reloadTasks: [Task<Void, Never>] = []
    let manager: RedditCredentialsManager
    let profile: SelectedAccountProfile

    init(_ account: RedditCredential) {
      let fetch = Fetch()
      var reload: (@MainActor () -> Void)?
      let manager = RedditCredentialsManager(credentials: [account], reloadSelectedProfile: { reload?() })
      self.fetch = fetch
      self.manager = manager
      profile = SelectedAccountProfile(currentAccount: { manager.selectedCredential }, fetch: fetch.call, persistUserName: { manager.backfillUserName($0, for: $1) })
      reload = { [weak self] in
        guard let self else { return }
        if let task = self.profile.reload() {
          self.reloadTasks.append(task)
        }
      }
    }
  }

  @Test func sameIDReplacementClearsThePublishedProfileBeforeFetching() async throws {
    let account = credential()
    let store = ProfileStore(account)
    store.manager.updateMe()
    let first = try #require(store.reloadTasks.last)
    await store.fetch.waitForCalls(1)
    try store.fetch.complete(0, with: user("placeholder-original-user"))
    await first.value
    #expect(store.profile.state == .ready)

    var replacement = account
    replacement.refreshToken = "placeholder-replacement-grant"
    withSelection(account.id) { store.manager.saveCred(replacement) }
    #expect(store.profile.user == nil)
    #expect(store.profile.state == .loading)
    try #require(store.reloadTasks.count == 2)
    let second = try #require(store.reloadTasks.last)
    await store.fetch.waitForCalls(2)
    try store.fetch.complete(1, with: user("placeholder-replacement-user"))
    await second.value
    #expect(store.profile.user?.data?.name == "placeholder-replacement-user")
    #expect(store.profile.state == .ready)
  }

  @Test(arguments: [false, true]) func sameIDReplacementDiscardsTheOldInFlightProfile(fails: Bool) async throws {
    let account = credential()
    let store = ProfileStore(account)
    store.manager.updateMe()
    let first = try #require(store.reloadTasks.last)
    await store.fetch.waitForCalls(1)

    let changes = Mutex(0)
    withObservationTracking {
      _ = store.profile.authorizationID
    } onChange: {
      changes.withLock { $0 += 1 }
    }
    var replacement = account
    replacement.refreshToken = "placeholder-replacement-grant"
    withSelection(account.id) { store.manager.saveCred(replacement) }
    let observed = changes.withLock { $0 }
    #expect(observed == 1)
    #expect(store.profile.authorizationID == replacement.authorizationID)
    try #require(store.reloadTasks.count == 2)
    let second = try #require(store.reloadTasks.last)
    await store.fetch.waitForCalls(2)
    try store.fetch.complete(1, with: user("placeholder-replacement-user"))
    await second.value
    try store.fetch.complete(0, with: fails ? nil : user("placeholder-stale-user"))
    await first.value
    #expect(store.profile.user?.data?.name == "placeholder-replacement-user")
    #expect(store.profile.state == .ready)
  }

  enum Logout: CaseIterable, Sendable { case delete, wipe, reject, saveCleared }

  @Test(arguments: Logout.allCases, [false, true]) func logoutClearsTheProfileAndDiscardsLateResults(logout: Logout, fails: Bool) async throws {
    let account = credential()
    let authorization = try #require(account.authorizationID)
    let store = ProfileStore(account)
    store.manager.updateMe()
    let first = try #require(store.reloadTasks.last)
    await store.fetch.waitForCalls(1)
    try store.fetch.complete(0, with: user("placeholder-original-user"))
    await first.value
    #expect(store.profile.user != nil)

    store.manager.updateMe()
    let pending = try #require(store.reloadTasks.last)
    await store.fetch.waitForCalls(2)
    switch logout {
    case .delete: store.manager.deleteCred(account)
    case .wipe: store.manager.wipeAllCredentials()
    case .reject: store.manager.updateAccessToken(nil, for: authorization)
    case .saveCleared:
      var cleared = account
      cleared.clearIdentity()
      withSelection(account.id) { store.manager.saveCred(cleared, forceCreate: false) }
    }
    #expect(store.profile.user == nil)
    #expect(store.profile.state == .signedOut)
    store.manager.updateAccessToken(token(), for: authorization)
    #expect(store.manager.selectedCredential?.authorizationID == nil)
    try store.fetch.complete(1, with: fails ? nil : user("placeholder-stale-user"))
    await pending.value
    #expect(store.profile.user == nil)
    #expect(store.profile.state == .signedOut)
  }
}

extension CredentialStoreMutationTests {
  @Test func installedSelectionDoesNotChangeWhenTheProfileInitializes() async throws {
    let account = credential()
    let manager = RedditCredentialsManager(credentials: [account])
    let profile = SelectedAccountProfile(currentAccount: { manager.selectedCredential(id: account.id) }, fetch: { _ in nil }, persistUserName: { _, _ in })
    let installed = try #require(manager.selectedCredential(id: account.id)?.authorizationID)
    #expect(profile.authorizationID == nil)
    let invalidated = Mutex(false)
    withObservationTracking {
      _ = manager.selectedCredential(id: account.id)?.authorizationID
    } onChange: {
      invalidated.withLock { $0 = true }
    }
    let task = profile.reload()
    #expect(profile.authorizationID == installed)
    #expect(!invalidated.withLock { $0 })
    await task?.value
    #expect(manager.selectedCredential(id: account.id)?.authorizationID == installed)
    #expect(!invalidated.withLock { $0 })
  }

  @Test func explicitSelectionUsesTheInstalledFallbackAndReplacementGrant() {
    let first = credential()
    let second = credential("placeholder-second-grant")
    let manager = RedditCredentialsManager(credentials: [first, second])
    #expect(manager.selectedCredential(id: nil) == first)
    #expect(manager.selectedCredential(id: UUID()) == first)
    #expect(manager.selectedCredential(id: second.id) == second)
    withSelection(second.id) { #expect(manager.selectedCredential == manager.selectedCredential(id: second.id)) }
    var replacement = first
    replacement.refreshToken = "placeholder-replacement-grant"
    withSelection(first.id) { manager.saveCred(replacement) }
    #expect(manager.selectedCredential(id: first.id)?.authorizationID == replacement.authorizationID)
    #expect(manager.selectedCredential(id: first.id)?.authorizationID != first.authorizationID)
    #expect(RedditCredentialsManager(credentials: []).selectedCredential(id: nil) == nil)
  }
}

extension CredentialStoreMutationTests {
  private func webCredential() -> RedditCredential {
    var account = RedditCredential(userName: "placeholder-web-user")
    account.signInMethod = .webSession
    account.webSessionCookies = "reddit_session=placeholder-original-session"
    return account
  }

  @Test func conditionalWebReplacementInvalidatesTheOldGrantBeforeReturning() throws {
    let account = webCredential()
    let original = try #require(account.authorizationID)
    var reloads = 0
    let manager = RedditCredentialsManager(credentials: [account], reloadSelectedProfile: { reloads += 1 })
    withSelection(account.id) {
      expectObservableMutation(manager) {
        manager.updateCred(account.id) {
          $0.webSessionCookies = "reddit_session=placeholder-replacement-session"
          return true
        }
      }
      #expect(!manager.containsAuthorization(original))
      #expect(manager.selectedCredential?.authorizationID != original)
      #expect(reloads == 1)
      manager.updateWebAccessToken(token(), cookies: account.webSessionCookies, renewedFrom: account.webSessionCookies!, for: original)
      #expect(manager.selectedCredential?.accessToken == nil)
    }
  }

  @Test func savingAnUntouchedWebDraftKeepsTheRotatedSession() throws {
    let account = webCredential()
    let authorization = try #require(account.authorizationID)
    let manager = RedditCredentialsManager(credentials: [account])
    var draft = account
    draft.userAgent = "placeholder-edited-agent"
    withSelection(account.id) {
      manager.updateWebAccessToken(token(), cookies: "reddit_session=placeholder-renewed-session", renewedFrom: account.webSessionCookies!, for: authorization)
      manager.saveDraft(draft, openedAs: account)
      #expect(manager.selectedCredential?.webSessionCookies == "reddit_session=placeholder-renewed-session")
      #expect(manager.selectedCredential?.accessToken == token())
      #expect(manager.selectedCredential?.authorizationID == authorization)
      #expect(manager.selectedCredential?.userAgent == draft.userAgent)
      #expect(manager.containsAuthorization(authorization))
    }
  }

  @Test func webSignOutInvalidatesItsLeaseAndKeepsAccountMetadata() throws {
    let account = webCredential()
    let authorization = try #require(account.authorizationID)
    var reloads = 0
    let manager = RedditCredentialsManager(credentials: [account], reloadSelectedProfile: { reloads += 1 })
    withSelection(account.id) {
      manager.updateWebAccessToken(nil, cookies: nil, renewedFrom: account.webSessionCookies!, for: authorization)
      #expect(!manager.containsAuthorization(authorization))
      #expect(manager.selectedCredential?.signInMethod == .webSession)
      #expect(manager.selectedCredential?.userName == account.userName)
      #expect(reloads == 1)
      manager.updateWebAccessToken(token(), cookies: account.webSessionCookies, renewedFrom: account.webSessionCookies!, for: authorization)
      #expect(manager.selectedCredential?.authorizationID == nil)
    }
  }

  @Test(arguments: [false, true]) func deletedWebAccountsCannotBeRestoredByDelayedConditionalWrites(wipe: Bool) throws {
    let account = webCredential()
    let authorization = try #require(account.authorizationID)
    let manager = RedditCredentialsManager(credentials: [account])
    withSelection(account.id) {
      manager.saveDraft(account, openedAs: account)
      if wipe {
        manager.wipeAllCredentials()
      } else {
        manager.deleteCred(account)
      }
      manager.updateCred(account.id) { $0.userAgent = "placeholder-stale-agent"
        return true
      }
      manager.updateWebAccessToken(token(), cookies: account.webSessionCookies, renewedFrom: account.webSessionCookies!, for: authorization)
      #expect(manager.credentials.isEmpty)
      #expect(!manager.containsAuthorization(authorization))
    }
  }
}
