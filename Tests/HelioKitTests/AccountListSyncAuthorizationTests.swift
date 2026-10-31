import CoreData
import Defaults
import Foundation
import Synchronization
import Testing
@testable import HelioKit

@MainActor
struct AccountListSyncAuthorizationTests {
  private func credential(_ grant: String = "placeholder-current-grant") -> RedditCredential {
    RedditCredential(apiAppID: "placeholder-client-id", refreshToken: grant, userName: "placeholder-user")
  }

  private func subscriptions(_ entries: [(String, String)]) throws -> [ListingChild<SubredditData>] {
    try entries.map { id, title in
      let json: [String: Any] = ["kind": "t5", "data": ["id": id, "name": "t5_\(id)", "url": "/r/\(id)/", "title": title, "public_description": ""]]
      return try JSONDecoder().decode(ListingChild<SubredditData>.self, from: JSONSerialization.data(withJSONObject: json))
    }
  }

  private func multis(_ entries: [(String, String)]) throws -> [RedditAPI.MultiContainerResponse] {
    try entries.map { id, title in
      let json: [String: Any] = ["kind": "LabeledMulti", "data": ["name": id, "path": "/user/placeholder-user/m/\(id)", "display_name": title, "subreddits": []]]
      return try JSONDecoder().decode(RedditAPI.MultiContainerResponse.self, from: JSONSerialization.data(withJSONObject: json))
    }
  }

  /// Package tests do not have the app bundle's Core Data model. Model just the two
  /// list entities, with the same attributes and relationship as the app model.
  private static let model: NSManagedObjectModel = {
    func entity(_ name: String, type: NSManagedObject.Type, strings: [String], booleans: [String]) -> NSEntityDescription {
      let entity = NSEntityDescription()
      entity.name = name
      entity.managedObjectClassName = NSStringFromClass(type)
      entity.properties = strings.map { attribute($0, type: .stringAttributeType) }
        + booleans.map { attribute($0, type: .booleanAttributeType, defaultValue: false) }
        + [attribute("helioCredentialID", type: .UUIDAttributeType)]
      return entity
    }
    func attribute(_ name: String, type: NSAttributeType, defaultValue: Any? = nil) -> NSAttributeDescription {
      let attribute = NSAttributeDescription()
      attribute.name = name
      attribute.attributeType = type
      attribute.isOptional = true
      attribute.defaultValue = defaultValue
      return attribute
    }
    let sub = entity("CachedSub", type: CachedSub.self, strings: [
      "banner_background_color", "banner_background_image", "banner_img", "community_icon", "display_name", "header_img", "icon_img", "key_color", "name", "primary_color", "title", "url", "user_flair_background_color", "uuid",
    ], booleans: [
      "allow_galleries", "allow_images", "allow_videos", "over18", "restrict_commenting", "user_has_favorited", "user_is_banned", "user_is_moderator", "user_is_subscriber",
    ])
    sub.properties.append(attribute("subscribers", type: .doubleAttributeType, defaultValue: 0))
    let multi = entity("CachedMulti", type: CachedMulti.self, strings: ["display_name", "icon_url", "key_color", "name", "path", "uuid"], booleans: ["over_18"])
    let subreddits = NSRelationshipDescription()
    subreddits.name = "subreddits"
    subreddits.destinationEntity = sub
    subreddits.maxCount = 0
    subreddits.deleteRule = .nullifyDeleteRule
    let membership = NSRelationshipDescription()
    membership.name = "multis"
    membership.destinationEntity = multi
    membership.maxCount = 0
    membership.deleteRule = .nullifyDeleteRule
    membership.inverseRelationship = subreddits
    subreddits.inverseRelationship = membership
    sub.properties.append(membership)
    multi.properties.append(subreddits)
    let model = NSManagedObjectModel()
    model.entities = [sub, multi]
    return model
  }()

  private func context() throws -> NSManagedObjectContext {
    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: Self.model)
    try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
    let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    context.persistentStoreCoordinator = coordinator
    return context
  }

  private func savedLists(in context: NSManagedObjectContext, account: RedditCredential) throws -> (subs: [String: String], multis: [String: String]) {
    let reader = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    reader.persistentStoreCoordinator = context.persistentStoreCoordinator
    return try reader.performAndWait {
      let subs = CachedSub.fetchRequest()
      subs.predicate = NSPredicate(format: "helioCredentialID == %@", account.id as CVarArg)
      let multis = CachedMulti.fetchRequest()
      multis.predicate = subs.predicate
      return try (
        Dictionary(uniqueKeysWithValues: reader.fetch(subs).map { ($0.uuid ?? "", $0.title ?? "") }),
        Dictionary(uniqueKeysWithValues: reader.fetch(multis).map { ($0.uuid ?? "", $0.display_name ?? "") }),
      )
    }
  }

  @Test(arguments: [false, true])
  func sameUUIDReauthorizationRejectsStaleSubscriptionWrites(emptyResponse: Bool) async throws {
    let old = credential("placeholder-old-grant")
    var replacement = old
    replacement.refreshToken = "placeholder-replacement-grant"
    let manager = RedditCredentialsManager(credentials: [replacement])
    let context = try context()
    let api = RedditAPI()
    let latest = try subscriptions([("shared", "Replacement title"), ("new", "Replacement only")])
    let seeded = await api.updateSubsInCoreData(with: latest, account: replacement, credentialsManager: manager, context: context)
    #expect(seeded)
    let before = try savedLists(in: context, account: replacement).subs

    // A completed old request arrives after the replacement sync: it would overwrite
    // shared metadata, insert old entries, and delete the replacement-only entry.
    let stale = try subscriptions(emptyResponse ? [] : [("shared", "Stale title"), ("old", "Stale only")])
    let accepted = await api.updateSubsInCoreData(with: stale, account: old, credentialsManager: manager, context: context)
    #expect(!accepted)
    #expect(try savedLists(in: context, account: replacement).subs == before)
    #expect(!context.performAndWait { context.hasChanges })
  }

  @Test(arguments: [false, true])
  func sameUUIDReauthorizationRejectsStaleMultiWrites(emptyResponse: Bool) async throws {
    let old = credential("placeholder-old-grant")
    var replacement = old
    replacement.refreshToken = "placeholder-replacement-grant"
    let manager = RedditCredentialsManager(credentials: [replacement])
    let context = try context()
    let api = RedditAPI()
    let latest = try multis([("shared", "Replacement title"), ("new", "Replacement only")])
    let seeded = await api.updateMultisInCoreData(with: latest, account: replacement, credentialsManager: manager, context: context)
    #expect(seeded)
    let before = try savedLists(in: context, account: replacement).multis
    let stale = try multis(emptyResponse ? [] : [("shared", "Stale title"), ("old", "Stale only")])
    let accepted = await api.updateMultisInCoreData(with: stale, account: old, credentialsManager: manager, context: context)
    #expect(!accepted)
    #expect(try savedLists(in: context, account: replacement).multis == before)
    #expect(!context.performAndWait { context.hasChanges })
  }

  @Test(arguments: [false, true])
  func removedOrRevokedGrantsCannotDeleteLists(revoked: Bool) async throws {
    let old = credential()
    let context = try context()
    let api = RedditAPI()
    let original = RedditCredentialsManager(credentials: [old])
    let subsSeeded = try await api.updateSubsInCoreData(with: subscriptions([("kept", "Kept")]), account: old, credentialsManager: original, context: context)
    let multisSeeded = try await api.updateMultisInCoreData(with: multis([("kept", "Kept")]), account: old, credentialsManager: original, context: context)
    #expect(subsSeeded && multisSeeded)
    var cleared = old
    cleared.clearIdentity()
    let manager = RedditCredentialsManager(credentials: revoked ? [cleared] : [])
    let before = try savedLists(in: context, account: old)
    let subsAccepted = await api.updateSubsInCoreData(with: [], account: old, credentialsManager: manager, context: context)
    let multisAccepted = await api.updateMultisInCoreData(with: [], account: old, credentialsManager: manager, context: context)
    #expect(!subsAccepted && !multisAccepted)
    let after = try savedLists(in: context, account: old)
    #expect(after.subs == before.subs && after.multis == before.multis)
  }

  @Test func aNonselectedCurrentGrantStillUpdatesAndDeletesListsAfterTokenRenewal() async throws {
    let selected = credential("placeholder-selected-grant")
    let captured = credential("placeholder-background-grant")
    var renewed = captured
    renewed.accessToken = .init(token: "placeholder-renewed-access-token", expiration: 3600, lastRefresh: Date())
    let manager = RedditCredentialsManager(credentials: [selected, renewed])
    #expect(manager.selectedCredential?.id == selected.id)
    let context = try context()
    let api = RedditAPI()
    for account in [selected, captured] {
      let subsSeeded = try await api.updateSubsInCoreData(with: subscriptions([("shared", "Before"), ("removed", "Removed")]), account: account, credentialsManager: manager, context: context)
      let multisSeeded = try await api.updateMultisInCoreData(with: multis([("shared", "Before"), ("removed", "Removed")]), account: account, credentialsManager: manager, context: context)
      #expect(subsSeeded && multisSeeded)
    }
    let selectedBefore = try savedLists(in: context, account: selected)
    let subsAccepted = try await api.updateSubsInCoreData(with: subscriptions([("shared", "After"), ("new", "New")]), account: captured, credentialsManager: manager, context: context)
    let multisAccepted = try await api.updateMultisInCoreData(with: multis([("shared", "After"), ("new", "New")]), account: captured, credentialsManager: manager, context: context)
    #expect(subsAccepted && multisAccepted)
    let saved = try savedLists(in: context, account: captured)
    #expect(saved.subs == ["t5_shared": "After", "t5_new": "New"])
    #expect(saved.multis == ["/user/placeholder-user/m/shared": "After", "/user/placeholder-user/m/new": "New"])
    let selectedAfter = try savedLists(in: context, account: selected)
    #expect(selectedAfter.subs == selectedBefore.subs && selectedAfter.multis == selectedBefore.multis)
  }

  @Test func syncCompletionRechecksGrantMembershipBeforeAdvancingTimestamp() {
    let captured = credential("placeholder-old-grant")
    let key = "\(captured.id.uuidString)|\(captured.userName ?? "")"
    defer { Defaults[.subsSyncedAt].removeValue(forKey: key) }
    let original = RedditCredentialsManager(credentials: [captured])
    let previous = Date(timeIntervalSince1970: 1)
    let originalAccepted = original.markSubscriptionsSynced(for: captured, at: previous)
    #expect(originalAccepted)
    var replacement = captured
    replacement.refreshToken = "placeholder-replacement-grant"
    let manager = RedditCredentialsManager(credentials: [replacement])
    // Both requests may have saved successfully before replacement; their later
    // completion must still not mark the replacement grant as freshly synced.
    let staleAccepted = manager.markSubscriptionsSynced(for: captured, at: Date(timeIntervalSince1970: 2))
    #expect(!staleAccepted)
    #expect(Defaults[.subsSyncedAt][key] == previous)
    let removedAccepted = RedditCredentialsManager(credentials: []).markSubscriptionsSynced(for: captured)
    #expect(!removedAccepted)
    #expect(Defaults[.subsSyncedAt][key] == previous)
    let current = Date(timeIntervalSince1970: 3)
    let nonselected = RedditCredentialsManager(credentials: [credential("placeholder-selected-grant"), replacement])
    let currentAccepted = nonselected.markSubscriptionsSynced(for: replacement, at: current)
    #expect(currentAccepted)
    #expect(Defaults[.subsSyncedAt][key] == current)
  }

  private func subreddit(_ id: String, subscribed: Bool = true, favorited: Bool = false) throws -> SubredditData {
    var data = try #require(subscriptions([(id, id)]).first?.data)
    data.display_name = id
    data.user_is_subscriber = subscribed
    data.user_has_favorited = favorited
    return data
  }

  private func savedSubscription(in context: NSManagedObjectContext, account: RedditCredential, fullname: String) throws -> SubredditData? {
    let reader = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    reader.persistentStoreCoordinator = context.persistentStoreCoordinator
    return try reader.performAndWait {
      let request = CachedSub.fetchRequest()
      request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
        NSPredicate(format: "helioCredentialID == %@", account.id as CVarArg),
        NSPredicate(format: "uuid == %@", fullname),
      ])
      return try reader.fetch(request).first.map { SubredditData(entity: $0) }
    }
  }

  @Test(arguments: [false, true])
  func persistenceRejectsLocalWritesFromAReplacedGrant(replacedClient: Bool) async throws {
    let captured = credential("placeholder-old-grant")
    var current = captured
    if replacedClient {
      current.apiAppID = "placeholder-replacement-client"
      current.refreshToken = "placeholder-current-grant"
    } else {
      current.refreshToken = "placeholder-current-grant"
    }
    let manager = RedditCredentialsManager(credentials: [current])
    let context = try context()
    let currentLists = try #require(AccountListPersistence(account: current, credentialsManager: manager, context: context))
    let staleLists = try #require(AccountListPersistence(account: captured, credentialsManager: manager, context: context))
    let data = try subreddit("kept")
    let accepted1 = await currentLists.replaceSubscriptions(with: [data])
    #expect(accepted1)
    let accepted2 = staleLists.setSubscription(false, subreddit: data)
    #expect(!accepted2)
    let accepted3 = try staleLists.setSubscription(true, subreddit: subreddit("stale-only"))
    #expect(!accepted3)
    let accepted4 = staleLists.setFavorite(true, fullname: data.name)
    #expect(!accepted4)
    let saved = try #require(try savedSubscription(in: context, account: current, fullname: data.name))
    #expect(saved.user_is_subscriber == true && saved.user_has_favorited == false)
    #expect(try savedLists(in: context, account: current).subs.count == 1)
    #expect(!context.performAndWait { context.hasChanges })
  }

  @Test(arguments: [false, true])
  func localWritesRejectRemovedAndRevokedGrants(revoked: Bool) throws {
    let captured = credential()
    let context = try context()
    let original = RedditCredentialsManager(credentials: [captured])
    let originalLists = try #require(AccountListPersistence(account: captured, credentialsManager: original, context: context))
    let data = try subreddit("kept")
    let accepted5 = originalLists.setSubscription(true, subreddit: data)
    #expect(accepted5)
    var cleared = captured
    cleared.clearIdentity()
    let manager = RedditCredentialsManager(credentials: revoked ? [cleared] : [])
    let staleLists = try #require(AccountListPersistence(account: captured, credentialsManager: manager, context: context))
    let accepted6 = staleLists.setSubscription(false, subreddit: data, expecting: true)
    #expect(!accepted6)
    let accepted7 = staleLists.setFavorite(true, fullname: data.name)
    #expect(!accepted7)
    #expect(try savedSubscription(in: context, account: captured, fullname: data.name)?.user_is_subscriber == true)
    #expect(AccountListPersistence(account: cleared, credentialsManager: manager, context: context) == nil)
    #expect(!context.performAndWait { context.hasChanges })
  }

  @Test func subscriptionsDeduplicateAndReplaceOnlyTheCapturedAccountsRows() async throws {
    let first = credential("placeholder-first-grant")
    let second = credential("placeholder-second-grant")
    let manager = RedditCredentialsManager(credentials: [first, second])
    let context = try context()
    let firstLists = try #require(AccountListPersistence(account: first, credentialsManager: manager, context: context))
    let secondLists = try #require(AccountListPersistence(account: second, credentialsManager: manager, context: context))
    let kept = try subreddit("kept")
    let accepted8 = try await firstLists.replaceSubscriptions(with: [kept, subreddit("removed")])
    #expect(accepted8)
    let accepted9 = await secondLists.replaceSubscriptions(with: [kept])
    #expect(accepted9)
    try context.performAndWait {
      _ = CachedSub(data: kept, context: context, credentialID: first.id)
      try context.save()
    }
    var updated = kept
    updated.title = "Updated"
    updated.user_has_favorited = true
    let accepted10 = try await firstLists.replaceSubscriptions(with: [updated, updated, subreddit("inserted")])
    #expect(accepted10)
    #expect(try savedLists(in: context, account: first).subs == ["t5_kept": "Updated", "t5_inserted": "inserted"])
    #expect(try savedSubscription(in: context, account: first, fullname: kept.name)?.user_has_favorited == true)
    #expect(try savedLists(in: context, account: second).subs == ["t5_kept": "kept"])
    let accepted11 = await firstLists.replaceSubscriptions(with: [])
    #expect(accepted11)
    #expect(try savedLists(in: context, account: first).subs.isEmpty)
    #expect(try savedLists(in: context, account: second).subs.count == 1)
  }

  @Test func multiMembersUseCapturedAccountAfterTokenRenewal() async throws {
    let selected = credential("placeholder-selected-grant")
    let captured = credential("placeholder-background-grant")
    var renewed = captured
    renewed.accessToken = .init(token: "placeholder-renewed-token", expiration: 3600, lastRefresh: Date())
    let manager = RedditCredentialsManager(credentials: [selected, renewed])
    let context = try context()
    let selectedLists = try #require(AccountListPersistence(account: selected, credentialsManager: manager, context: context))
    let capturedLists = try #require(AccountListPersistence(account: captured, credentialsManager: manager, context: context))
    let shared = try subreddit("shared")
    let accepted12 = await selectedLists.replaceSubscriptions(with: [shared])
    #expect(accepted12)
    let accepted13 = await capturedLists.replaceSubscriptions(with: [shared])
    #expect(accepted13)
    let multiOnly = try subreddit("multi-only", subscribed: false)
    var multi = try #require(multis([("kept", "Before")]).first?.data)
    multi.subreddits = [MultiSub(name: "shared", data: shared), MultiSub(name: "multi-only", data: multiOnly)]
    let accepted14 = await capturedLists.replaceMultis(with: [multi])
    #expect(accepted14)
    let reader = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    reader.persistentStoreCoordinator = context.persistentStoreCoordinator
    let members = try reader.performAndWait {
      let request = CachedMulti.fetchRequest()
      request.predicate = NSPredicate(format: "helioCredentialID == %@", captured.id as CVarArg)
      return try reader.fetch(request).first?.subsArray.map { ($0.uuid, $0.helioCredentialID) } ?? []
    }
    #expect(Set(members.compactMap(\.0)) == [shared.name, multiOnly.name])
    #expect(members.allSatisfy { $0.1 == captured.id })
    #expect(try savedLists(in: context, account: selected).subs == ["t5_shared": "shared"])
    let accepted15 = capturedLists.setSubscription(true, subreddit: multiOnly)
    #expect(accepted15)
    #expect(try savedSubscription(in: context, account: captured, fullname: multiOnly.name)?.user_is_subscriber == true)
  }

  @Test func localWritesSaveExplicitStateAndGuardRollback() throws {
    let selected = credential("placeholder-selected-grant")
    let captured = credential("placeholder-background-grant")
    var renewed = captured
    renewed.accessToken = .init(token: "placeholder-renewed-token", expiration: 3600, lastRefresh: Date())
    let manager = RedditCredentialsManager(credentials: [selected, renewed])
    let context = try context()
    let selectedLists = try #require(AccountListPersistence(account: selected, credentialsManager: manager, context: context))
    let lists = try #require(AccountListPersistence(account: captured, credentialsManager: manager, context: context))
    let data = try subreddit("shared", favorited: true)
    let accepted16 = selectedLists.setSubscription(true, subreddit: data)
    #expect(accepted16)
    let accepted17 = lists.setSubscription(true, subreddit: data)
    #expect(accepted17)
    let accepted18 = lists.setFavorite(false, fullname: data.name)
    #expect(accepted18)
    let accepted19 = lists.setFavorite(true, fullname: data.name, expecting: false)
    #expect(accepted19)
    var staleSnapshot = data
    staleSnapshot.user_has_favorited = false
    let accepted20 = lists.setSubscription(true, subreddit: staleSnapshot)
    #expect(accepted20)
    // A later local update already restored true; a stale failure expecting false
    // must not write false over it.
    let accepted21 = lists.setFavorite(false, fullname: data.name, expecting: false)
    #expect(!accepted21)
    #expect(try savedSubscription(in: context, account: captured, fullname: data.name)?.user_has_favorited == true)
    let accepted22 = lists.setSubscription(false, subreddit: data)
    #expect(accepted22)
    let accepted23 = lists.setFavorite(false, fullname: data.name)
    #expect(!accepted23)
    let accepted24 = lists.setSubscription(false, subreddit: data, expecting: true)
    #expect(!accepted24)
    let accepted25 = lists.setSubscription(true, subreddit: data, expecting: false)
    #expect(accepted25)
    #expect(try savedSubscription(in: context, account: captured, fullname: data.name)?.user_is_subscriber == true)
    #expect(try savedSubscription(in: context, account: selected, fullname: data.name)?.user_has_favorited == true)
    #expect(!context.performAndWait { context.hasChanges })
  }

  @Test func directMultiReplacementSavesUpdatesInsertsAndDeletes() async throws {
    let account = credential()
    let manager = RedditCredentialsManager(credentials: [account])
    let context = try context()
    let lists = try #require(AccountListPersistence(account: account, credentialsManager: manager, context: context))
    let before = try multis([("kept", "Before"), ("removed", "Removed")]).compactMap(\.data)
    let accepted26 = await lists.replaceMultis(with: before)
    #expect(accepted26)
    let after = try multis([("kept", "After"), ("inserted", "Inserted")]).compactMap(\.data)
    let accepted27 = await lists.replaceMultis(with: after)
    #expect(accepted27)
    #expect(try savedLists(in: context, account: account).multis == [
      "/user/placeholder-user/m/kept": "After", "/user/placeholder-user/m/inserted": "Inserted",
    ])
    let accepted28 = await lists.replaceMultis(with: [])
    #expect(accepted28)
    #expect(try savedLists(in: context, account: account).multis.isEmpty)
  }

  @Test func deviceLocalFavoritesPersistRemoval() throws {
    let previous = Defaults[.likedButNotSubbed]
    defer { Defaults[.likedButNotSubbed] = previous }
    let sub = try Subreddit(data: subreddit("placeholder-local-favorite", subscribed: false))
    Defaults[.likedButNotSubbed] = []
    #expect(sub.localFavoriteToggle())
    #expect(Defaults[.likedButNotSubbed].contains { $0.id == sub.id })
    #expect(!sub.localFavoriteToggle())
    #expect(Defaults[.likedButNotSubbed].isEmpty)
  }
}

extension AccountListSyncAuthorizationTests {
  /// Pauses only the private context queue, never the UI actor. The deadline is
  /// a deadlock guard, not a performance assertion.
  private final class CommitGate: @unchecked Sendable {
    private struct State {
      var started = false
      var timedOut = false
      var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())
    private let condition = NSCondition()
    private var released = false

    func pause() {
      let waiters = state.withLock { value in
        value.started = true
        let waiters = value.waiters
        value.waiters = []
        return waiters
      }
      waiters.forEach { $0.resume() }
      condition.lock()
      let deadline = Date().addingTimeInterval(10)
      while !released {
        if !condition.wait(until: deadline) {
          state.withLock { $0.timedOut = true }
          break
        }
      }
      condition.unlock()
    }

    func waitUntilPaused() async {
      await withCheckedContinuation { continuation in
        let ready = state.withLock { value in
          if value.started {
            return true
          }
          value.waiters.append(continuation)
          return false
        }
        if ready {
          continuation.resume()
        }
      }
    }

    func release() {
      condition.lock()
      released = true
      condition.broadcast()
      condition.unlock()
    }

    var timedOut: Bool {
      state.withLock { $0.timedOut }
    }
  }

  @Test(arguments: [false, true])
  func bulkReconciliationLeavesTheUIActorFreeAndChecksTheGrantAtCommit(replaceGrant: Bool) async throws {
    let captured = credential()
    let manager = RedditCredentialsManager(credentials: [captured])
    let context = try context()
    let initial = try #require(AccountListPersistence(account: captured, credentialsManager: manager, context: context))
    let seeded = try await initial.replaceSubscriptions(with: [subreddit("original")])
    #expect(seeded)
    let gate = CommitGate()
    let candidate = AccountListPersistence(account: captured, credentialsManager: manager, context: context, beforeBulkCommit: { gate.pause() })
    let lists = try #require(candidate)
    let data = try subreddit("new")
    let task = Task { await lists.replaceSubscriptions(with: [data]) }
    await gate.waitUntilPaused()
    defer { gate.release() }
    // This main-actor turn must be able to execute while reconciliation is paused.
    #expect(Thread.isMainThread)
    #expect(!gate.timedOut)
    var updated = captured
    if replaceGrant {
      updated.refreshToken = "placeholder-replacement-grant"
    } else {
      updated.userName = "placeholder-edited-name"
    }
    manager.saveCred(updated)
    gate.release()
    let saved = await task.value
    #expect(saved == !replaceGrant)
    #expect(manager.credentials == [updated])
    let rows = try savedLists(in: context, account: captured).subs
    #expect(rows == (replaceGrant ? ["t5_original": "original"] : ["t5_new": "new"]))
    #expect(!context.performAndWait { context.hasChanges })
  }

  @Test func subscriptionChangesKeepMultiMembershipAndUseAccountScopedState() async throws {
    let captured = credential()
    let other = credential("placeholder-other-grant")
    let manager = RedditCredentialsManager(credentials: [captured, other])
    let context = try context()
    let lists = try #require(AccountListPersistence(account: captured, credentialsManager: manager, context: context))
    let otherLists = try #require(AccountListPersistence(account: other, credentialsManager: manager, context: context))
    let shared = try subreddit("shared")
    let first = await lists.replaceSubscriptions(with: [shared])
    let second = otherLists.setSubscription(true, subreddit: shared)
    #expect(first && second)
    var multi = try #require(multis([("kept", "Kept")]).first?.data)
    multi.subreddits = [MultiSub(name: "shared", data: shared)]
    let multiSaved = await lists.replaceMultis(with: [multi])
    #expect(multiSaved)
    let emptied = await lists.replaceSubscriptions(with: [])
    #expect(emptied)
    #expect(!lists.isSubscribed(fullname: shared.name))
    #expect(otherLists.isSubscribed(fullname: shared.name))
    let subscribed = lists.setSubscription(true, subreddit: shared)
    let unsubscribed = lists.setSubscription(false, subreddit: shared)
    #expect(subscribed && unsubscribed)
    let members = try context.performAndWait {
      let request = CachedMulti.fetchRequest()
      request.predicate = NSPredicate(format: "helioCredentialID == %@", captured.id as CVarArg)
      return try context.fetch(request).first?.subsArray.map(\.name) ?? []
    }
    #expect(members == [shared.name])
  }

  @Test func failedFavoriteIntentsNeverUseAnUnconfirmedRollbackBaseline() throws {
    let captured = credential()
    let manager = RedditCredentialsManager(credentials: [captured])
    let context = try context()
    let lists = try #require(AccountListPersistence(account: captured, credentialsManager: manager, context: context))
    let data = try subreddit("shared")
    #expect(lists.setSubscription(true, subreddit: data))
    let first = try #require(lists.beginMutation(fullname: data.name))
    #expect(lists.setFavorite(true, fullname: data.name))
    // A second false intent cannot begin from the unconfirmed true value.
    #expect(lists.beginMutation(fullname: data.name) == nil)
    #expect(lists.isCurrent(first))
    #expect(lists.setFavorite(false, fullname: data.name, expecting: true))
    lists.finish(first)
    let next = try #require(lists.beginMutation(fullname: data.name))
    defer { lists.finish(next) }
    lists.finish(first)
    #expect(lists.isCurrent(next))
    #expect(lists.setFavorite(true, fullname: data.name))
    #expect(lists.setFavorite(false, fullname: data.name, expecting: true))
    #expect(try savedSubscription(in: context, account: captured, fullname: data.name)?.user_has_favorited == false)
  }

  @Test func failedUnsubscribeDoesNotAdmitAnOverlappingNonoptimisticSubscribe() throws {
    let captured = credential()
    let manager = RedditCredentialsManager(credentials: [captured])
    let context = try context()
    let lists = try #require(AccountListPersistence(account: captured, credentialsManager: manager, context: context))
    let data = try subreddit("shared")
    #expect(lists.setSubscription(true, subreddit: data))
    let first = try #require(lists.beginMutation(fullname: data.name))
    #expect(lists.setSubscription(false, subreddit: data))
    // This includes the favorite surface: every action on this row is reserved.
    #expect(lists.beginMutation(fullname: data.name) == nil)
    #expect(lists.setSubscription(true, subreddit: data, expecting: false))
    lists.finish(first)
    let next = try #require(lists.beginMutation(fullname: data.name))
    defer { lists.finish(next) }
    #expect(lists.isSubscribed(fullname: data.name))
    // A failed nonoptimistic unsubscribe makes no local write.
    #expect(try savedSubscription(in: context, account: captured, fullname: data.name)?.user_is_subscriber == true)
  }

  @Test func mutationReservationsDoNotBlockAnotherAccountOrSubreddit() throws {
    let firstAccount = credential()
    let secondAccount = credential()
    let manager = RedditCredentialsManager(credentials: [firstAccount, secondAccount])
    let first = try #require(AccountListPersistence(account: firstAccount, credentialsManager: manager))
    let second = try #require(AccountListPersistence(account: secondAccount, credentialsManager: manager))
    let a = try #require(first.beginMutation(fullname: "t5_shared"))
    let b = try #require(second.beginMutation(fullname: "t5_shared"))
    let c = try #require(first.beginMutation(fullname: "t5_other"))
    defer { first.finish(a)
      second.finish(b)
      first.finish(c)
    }
    #expect(first.isCurrent(a) && second.isCurrent(b) && first.isCurrent(c))
  }
}

extension AccountListSyncAuthorizationTests {
  private enum FailedLocalWrite: CaseIterable { case insertSubscription, updateSubscription, deleteSubscription, favorite }

  @Test(arguments: FailedLocalWrite.allCases)
  private func aFailedLocalSaveCannotLeaveAnUnsentActionInTheSharedContext(operation: FailedLocalWrite) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: Self.model)
    let url = directory.appendingPathComponent("lists.sqlite")
    let writable = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url)
    let source = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
    source.persistentStoreCoordinator = coordinator
    let account = credential()
    let targetData = try subreddit("shared", subscribed: operation != .updateSubscription)
    _ = CachedSub(data: targetData, context: source, credentialID: account.id)
    _ = try CachedSub(data: subreddit("unrelated"), context: source, credentialID: account.id)
    try source.save()
    source.reset()
    try coordinator.remove(writable)
    _ = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: [NSReadOnlyPersistentStoreOption: true])
    let rows = try source.fetch(CachedSub.fetchRequest())
    let target = try #require(rows.first { $0.name == targetData.name })
    let unrelated = try #require(rows.first { $0.name == "t5_unrelated" })
    unrelated.title = "Unrelated pending edit"
    let manager = RedditCredentialsManager(credentials: [account])
    let owner = try #require(AccountListPersistence(account: account, credentialsManager: manager, context: source))
    let accepted: Bool = switch operation {
    case .insertSubscription:
      try owner.setSubscription(true, subreddit: subreddit("new"))
    case .updateSubscription:
      owner.setSubscription(true, subreddit: targetData)
    case .deleteSubscription:
      owner.setSubscription(false, subreddit: targetData)
    case .favorite:
      owner.setFavorite(true, fullname: targetData.name)
    }
    #expect(!accepted)
    #expect(source.insertedObjects.isEmpty)
    #expect(source.deletedObjects.isEmpty)
    #expect(!target.hasChanges)
    #expect(target.user_is_subscriber == (operation != .updateSubscription))
    #expect(!target.user_has_favorited)
    #expect(unrelated.title == "Unrelated pending edit")
    #expect(source.updatedObjects == [unrelated])
    let stored = try savedSubscription(in: source, account: account, fullname: targetData.name)
    #expect(stored?.user_is_subscriber == (operation != .updateSubscription))
    #expect(stored?.user_has_favorited == false)
    #expect(try savedLists(in: source, account: account).subs["t5_new"] == nil)
  }

  @Test func aSuccessfulLocalSaveMergesImmediatelyWithoutSavingUnrelatedPendingEdits() throws {
    let account = credential()
    let manager = RedditCredentialsManager(credentials: [account])
    let source = try context()
    let owner = try #require(AccountListPersistence(account: account, credentialsManager: manager, context: source))
    let data = try subreddit("shared")
    let seeded = owner.setSubscription(true, subreddit: data)
    #expect(seeded)
    let pending = try source.performAndWait {
      let request = CachedSub.fetchRequest()
      request.predicate = NSPredicate(format: "name == %@", data.name)
      let rows = try source.fetch(request)
      let target = try #require(rows.first)
      let unrelated = try CachedSub(data: subreddit("unrelated"), context: source, credentialID: account.id)
      try source.save()
      target.title = "Pending metadata on the changed row"
      unrelated.title = "Unrelated pending edit"
      return (target: target, unrelated: unrelated)
    }
    let saved = owner.setFavorite(true, fullname: data.name)
    #expect(saved)
    #expect(owner.isSubscribed(fullname: data.name))
    #expect(try savedSubscription(in: source, account: account, fullname: data.name)?.user_has_favorited == true)
    #expect(source.performAndWait {
      pending.target.title == "Pending metadata on the changed row" && pending.unrelated.title == "Unrelated pending edit" && source.hasChanges
    })
    let stored = try savedLists(in: source, account: account).subs
    #expect(stored["t5_shared"] == "shared")
    #expect(stored["t5_unrelated"] == "unrelated")
  }
}
