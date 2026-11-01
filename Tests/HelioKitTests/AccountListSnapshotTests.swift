import CoreData
import Foundation
import Testing
@testable import HelioKit

extension AccountListSyncAuthorizationTests {
  @Test func staleSubscriptionSnapshotsCannotRestoreAnUnsubscribeOrDeleteANewSubscription() async throws {
    let account = credential()
    let manager = RedditCredentialsManager(credentials: [account])
    let context = try context()
    let owner = try #require(AccountListPersistence(account: account, credentialsManager: manager, context: context))
    let removed = try subreddit("removed")
    let added = try subreddit("added")
    let seeded = await owner.replaceSubscriptions(with: [removed])
    #expect(seeded)
    let snapshot = owner.captureSnapshot()
    let unsubscribed = await owner.setSubscription(false, subreddit: removed)
    let subscribed = await owner.setSubscription(true, subreddit: added)
    #expect(unsubscribed && subscribed)
    let oldResponse = await owner.replaceSubscriptions(with: [removed], snapshot: snapshot)
    #expect(oldResponse)
    #expect(try savedSubscription(in: context, account: account, fullname: removed.name) == nil)
    #expect(try savedSubscription(in: context, account: account, fullname: added.name)?.user_is_subscriber == true)
    // A later, fresh authoritative sync is not pinned to old local revisions.
    let freshResponse = await owner.replaceSubscriptions(with: [])
    #expect(freshResponse)
    #expect(try savedLists(in: context, account: account).subs.isEmpty)
  }

  @Test(arguments: [false, true]) func staleFavoriteSnapshotsPreserveChangesAndInFlightFetches(startedDuringMutation: Bool) async throws {
    let account = credential()
    let manager = RedditCredentialsManager(credentials: [account])
    let context = try context()
    let owner = try #require(AccountListPersistence(account: account, credentialsManager: manager, context: context))
    let original = try subreddit("shared", favorited: false)
    let seeded = await owner.replaceSubscriptions(with: [original])
    #expect(seeded)
    let earlier = owner.captureSnapshot()
    let ticket = try #require(owner.beginMutation(fullname: original.name))
    let changed = await owner.setFavorite(true, fullname: original.name, expecting: false)
    #expect(changed)
    let snapshot = startedDuringMutation ? owner.captureSnapshot() : earlier
    owner.finish(ticket)
    let oldResponse = await owner.replaceSubscriptions(with: [original], snapshot: snapshot)
    #expect(oldResponse)
    #expect(try savedSubscription(in: context, account: account, fullname: original.name)?.user_has_favorited == true)
    let freshResponse = await owner.replaceSubscriptions(with: [original])
    #expect(freshResponse)
    #expect(try savedSubscription(in: context, account: account, fullname: original.name)?.user_has_favorited == false)
  }

  @Test func staleMultiSnapshotsDoNotRecreateSubscribedOrFavoriteFlagsAfterLocalDeletion() async throws {
    let account = credential()
    let manager = RedditCredentialsManager(credentials: [account])
    let context = try context()
    let owner = try #require(AccountListPersistence(account: account, credentialsManager: manager, context: context))
    let original = try subreddit("shared", favorited: true)
    let seeded = await owner.replaceSubscriptions(with: [original])
    #expect(seeded)
    let snapshot = owner.captureSnapshot()
    let deleted = await owner.setSubscription(false, subreddit: original)
    #expect(deleted)
    var multi = try #require(multis([("shared-list", "Shared list")]).first?.data)
    multi.subreddits = [MultiSub(name: "shared", data: original)]
    let oldResponse = await owner.replaceMultis(with: [multi], snapshot: snapshot)
    #expect(oldResponse)
    let stored = try savedSubscription(in: context, account: account, fullname: original.name)
    #expect(stored?.user_is_subscriber == false)
    #expect(stored?.user_has_favorited == false)
    let cleaned = await owner.replaceMultis(with: [])
    #expect(cleaned)
    #expect(try savedSubscription(in: context, account: account, fullname: original.name) == nil)
  }

  @Test func aStaleMultiRemovalPrunesARowUnsubscribedAfterItsSnapshot() async throws {
    let account = credential()
    let manager = RedditCredentialsManager(credentials: [account])
    let context = try context()
    let owner = try #require(AccountListPersistence(account: account, credentialsManager: manager, context: context))
    let original = try subreddit("shared", favorited: true)
    var multi = try #require(multis([("shared-list", "Shared list")]).first?.data)
    multi.subreddits = [MultiSub(name: "shared", data: original)]
    #expect(await owner.replaceMultis(with: [multi]))
    let snapshot = owner.captureSnapshot()
    #expect(await owner.setSubscription(false, subreddit: original))
    #expect(try savedSubscription(in: context, account: account, fullname: original.name)?.user_is_subscriber == false)
    #expect(await owner.replaceMultis(with: [], snapshot: snapshot))
    #expect(try savedSubscription(in: context, account: account, fullname: original.name) == nil)
  }

  @Test(arguments: [false, true]) func failedOptimisticUnsubscribeRestoresThePersistedFavoriteAfterMultiRecreation(pruneRecreatedRow: Bool) async throws {
    let account = credential()
    let manager = RedditCredentialsManager(credentials: [account])
    let context = try context()
    let owner = try #require(AccountListPersistence(account: account, credentialsManager: manager, context: context))
    let original = try subreddit("shared", favorited: true)
    #expect(await owner.replaceSubscriptions(with: [original]))
    let snapshot = owner.captureSnapshot()
    let ticket = try #require(owner.beginMutation(fullname: original.name))
    defer { owner.finish(ticket) }
    // The view's favorite can be stale; rollback must use the persisted baseline.
    var staleView = original
    staleView.user_has_favorited = false
    let change = try #require(await owner.optimisticallySetSubscription(false, subreddit: staleView, expecting: true))
    #expect(change.previousFavorite)
    #expect(try savedSubscription(in: context, account: account, fullname: original.name) == nil)
    var multi = try #require(multis([("shared-list", "Shared list")]).first?.data)
    multi.subreddits = [MultiSub(name: "shared", data: original)]
    #expect(await owner.replaceMultis(with: [multi], snapshot: snapshot))
    #expect(try savedSubscription(in: context, account: account, fullname: original.name)?.user_has_favorited == false)
    if pruneRecreatedRow {
      #expect(await owner.replaceMultis(with: [], snapshot: snapshot))
      #expect(try savedSubscription(in: context, account: account, fullname: original.name) == nil)
    }
    #expect(await owner.rollbackSubscription(change))
    let restored = try savedSubscription(in: context, account: account, fullname: original.name)
    #expect(restored?.user_is_subscriber == true)
    #expect(restored?.user_has_favorited == true)
    // Receipts are single-use; their own successful rollback advances the revision.
    #expect(await owner.rollbackSubscription(change) == false)
  }

  @Test(arguments: [false, true]) func aSubscriptionRollbackCannotOverwriteANewerLocalRowWrite(newerSubscription: Bool) async throws {
    let account = credential()
    let manager = RedditCredentialsManager(credentials: [account])
    let context = try context()
    let owner = try #require(AccountListPersistence(account: account, credentialsManager: manager, context: context))
    let original = try subreddit("shared", favorited: true)
    #expect(await owner.replaceSubscriptions(with: [original]))
    let ticket = try #require(owner.beginMutation(fullname: original.name))
    defer { owner.finish(ticket) }
    let snapshot = owner.captureSnapshot()
    let change = try #require(await owner.optimisticallySetSubscription(false, subreddit: original, expecting: true))
    var multi = try #require(multis([("shared-list", "Shared list")]).first?.data)
    multi.subreddits = [MultiSub(name: "shared", data: original)]
    #expect(await owner.replaceMultis(with: [multi], snapshot: snapshot))
    if newerSubscription {
      #expect(await owner.setSubscription(true, subreddit: original))
    } else {
      #expect(await owner.setFavorite(false, fullname: original.name))
    }
    #expect(await owner.rollbackSubscription(change) == false)
    let stored = try savedSubscription(in: context, account: account, fullname: original.name)
    #expect(stored?.user_is_subscriber == newerSubscription)
    #expect(stored?.user_has_favorited == false)
  }

  @Test func anUnavailableSubscriptionStoreIsUnknownRatherThanAnAbsentSubscription() async throws {
    let account = credential()
    let manager = RedditCredentialsManager(credentials: [account])
    let context = try context()
    let owner = try #require(AccountListPersistence(account: account, credentialsManager: manager, context: context))
    #expect(await owner.isSubscribed(fullname: "t5_shared") == false)
    let data = try subreddit("shared")
    let seeded = await owner.setSubscription(true, subreddit: data)
    #expect(seeded)
    try context.performAndWait {
      context.reset()
      let coordinator = try #require(context.persistentStoreCoordinator)
      for store in coordinator.persistentStores {
        try coordinator.remove(store)
      }
    }
    #expect(await owner.isSubscribed(fullname: data.name) == nil)
  }
}
