import CoreData
import Foundation
import os
import Synchronization

/// A captured account's subscription and multi lists. Selection is not ownership: a
/// still-installed grant may finish syncing even after another account is selected.
@MainActor
struct AccountListPersistence {
  fileprivate struct MutationKey: Hashable {
    let authorization: RedditCredential.AuthorizationID
    let fullname: String
  }

  struct MutationTicket {
    fileprivate let key: MutationKey
    fileprivate let id: UUID
  }

  struct Snapshot: Sendable {
    fileprivate let authorization: RedditCredential.AuthorizationID
    fileprivate let revision: UInt64
    fileprivate let activeRows: Set<String>
  }

  private struct StateRevisions: Sendable {
    var revision: UInt64 = 0
    var rows: [RedditCredential.AuthorizationID: [String: UInt64]] = [:]
  }

  private final class RevisionLedger: Sendable {
    let value = Mutex(StateRevisions())

    func protectedRows(for snapshot: Snapshot) -> Set<String> {
      let rows = value.withLock { $0.rows[snapshot.authorization] ?? [:] }
      return Set(rows.filter { $0.value > snapshot.revision }.map(\.key)).union(snapshot.activeRows)
    }
  }

  /// This lock covers only small revision bookkeeping, never disk/network work.
  private static let stateRevisions = RevisionLedger()

  func captureSnapshot() -> Snapshot {
    let revision = Self.stateRevisions.value.withLock { $0.revision }
    let active = Self.mutations.keys.filter { $0.authorization == authorization }.map(\.fullname)
    return Snapshot(authorization: authorization, revision: revision, activeRows: Set(active))
  }

  private static var mutations: [MutationKey: UUID] = [:]

  nonisolated let credential: RedditCredential
  private let authorization: RedditCredential.AuthorizationID
  private let credentialsManager: RedditCredentialsManager
  private let context: NSManagedObjectContext?
  private let beforeBulkCommit: (@Sendable () -> Void)?

  init?(
    account: RedditCredential,
    credentialsManager: RedditCredentialsManager = .shared,
    context: NSManagedObjectContext? = nil,
    beforeBulkCommit: (@Sendable () -> Void)? = nil,
  ) {
    guard let authorization = account.authorizationID else { return nil }
    credential = account
    self.authorization = authorization
    self.credentialsManager = credentialsManager
    self.context = context
    self.beforeBulkCommit = beforeBulkCommit
  }

  private var authorizationIsInstalled: Bool {
    // UI-owned checks must not wait for the lease held by a background disk save.
    credentialsManager.credentials.contains { $0.authorizationID == authorization }
  }

  func beginMutation(fullname: String) -> MutationTicket? {
    guard authorizationIsInstalled else { return nil }
    let key = MutationKey(authorization: authorization, fullname: fullname)
    // An optimistic value is not a confirmed baseline for another operation.
    // Subscription and favorite gestures share this reservation because removing
    // a subscription may remove the row that a pending favorite would roll back.
    guard Self.mutations[key] == nil else { return nil }
    let id = UUID()
    Self.mutations[key] = id
    return MutationTicket(key: key, id: id)
  }

  func isCurrent(_ ticket: MutationTicket) -> Bool {
    ticket.key.authorization == authorization && Self.mutations[ticket.key] == ticket.id && authorizationIsInstalled
  }

  func finish(_ ticket: MutationTicket) {
    if Self.mutations[ticket.key] == ticket.id {
      Self.mutations.removeValue(forKey: ticket.key)
    }
  }

  func isSubscribed(fullname: String) async -> Bool? {
    let source = context ?? PersistenceController.shared.accountListsContext
    let manager = credentialsManager
    let authorization = authorization
    let credentialID = credential.id
    return await source.perform { () -> Bool? in
      guard manager.containsAuthorization(authorization),
            let coordinator = source.persistentStoreCoordinator, !coordinator.persistentStores.isEmpty
      else { return nil }
      do {
        return try source.fetch(requestForSubreddit(credentialID, fullname: fullname)).contains(where: \.user_is_subscriber)
      } catch {
        Logger(subsystem: "com.sertacozercan.helio", category: "AccountListPersistence")
          .error("Failed to read subscription baseline: \(error.localizedDescription)")
        return nil
      }
    }
  }

  @discardableResult
  func replaceSubscriptions(with subscriptions: [SubredditData], snapshot: Snapshot? = nil) async -> Bool {
    let snapshot = snapshot ?? captureSnapshot()
    guard snapshot.authorization == authorization else { return false }
    let revisions = Self.stateRevisions
    let credentialID = credential.id
    return await bulkTransaction { context in
      let request = CachedSub.fetchRequest()
      request.predicate = predicateForAccount(credentialID)
      let existing = try context.fetch(request)

      let protected = revisions.protectedRows(for: snapshot)
      // CloudKit may deliver duplicate rows. Keep one per Reddit fullname, as the
      // subscription sync did before, without touching another account's rows.
      var byID: [String: CachedSub] = [:]
      for sub in existing {
        let id = sub.uuid ?? ""
        if let kept = byID[id] {
          kept.multis = (kept.multis ?? []).union(sub.multis ?? [])
          context.delete(sub)
        } else {
          byID[id] = sub
        }
      }
      for var data in subscriptions {
        // Membership in this endpoint is authoritative even when the optional
        // user flag is omitted from a listing entry.
        data.user_is_subscriber = true
        // An optimistic unsubscribe may already have removed this row. Do not
        // recreate it from a response whose fetch began before the mutation.
        if protected.contains(data.name), byID[data.name] == nil {
          continue
        }
        let sub = byID[data.name] ?? CachedSub(context: context)
        let currentState = protected.contains(data.name) ? (sub.user_is_subscriber, sub.user_has_favorited) : nil
        sub.update(data: data, credentialID: credentialID)
        if let currentState {
          sub.user_is_subscriber = currentState.0
          sub.user_has_favorited = currentState.1
        }
        byID[data.name] = sub
      }
      let fetchedIDs = Set(subscriptions.map(\.name))
      for (id, sub) in byID where !fetchedIDs.contains(id) && !protected.contains(id) {
        if sub.multis?.isEmpty == false {
          sub.user_is_subscriber = false
        } else {
          context.delete(sub)
        }
      }
      return true
    }
  }

  @discardableResult
  func replaceMultis(with multis: [MultiData], snapshot: Snapshot? = nil) async -> Bool {
    let snapshot = snapshot ?? captureSnapshot()
    guard snapshot.authorization == authorization else { return false }
    let revisions = Self.stateRevisions
    let credentialID = credential.id
    return await bulkTransaction { context in
      let request = CachedMulti.fetchRequest()
      request.predicate = predicateForAccount(credentialID)
      let existing = try context.fetch(request)
      let protected = revisions.protectedRows(for: snapshot)
      for var data in multis {
        data.subreddits = data.subreddits?.map { sub in
          var sub = sub
          if let fullname = sub.data?.name, protected.contains(fullname) {
            // Existing members are reused with their current state. A member
            // recreated after a local deletion must not regain stale flags.
            sub.data?.user_is_subscriber = false
            sub.data?.user_has_favorited = false
          }
          return sub
        }
        if let multi = existing.first(where: { $0.uuid == data.id }) {
          multi.update(data, credentialID: credentialID)
        } else {
          _ = CachedMulti(data: data, context: context, credentialID: credentialID)
        }
      }
      let fetchedIDs = Set(multis.map(\.id))
      for multi in existing where !fetchedIDs.contains(multi.uuid ?? "") {
        context.delete(multi)
      }
      context.processPendingChanges()
      let subRequest = CachedSub.fetchRequest()
      subRequest.predicate = predicateForAccount(credentialID)
      for sub in try context.fetch(subRequest) where !sub.user_is_subscriber && !protected.contains(sub.uuid ?? "") {
        // Removing a multi/member may orphan a row retained by subscription sync.
        if sub.multis?.contains(where: { !$0.isDeleted }) != true {
          context.delete(sub)
        }
      }
      return true
    }
  }

  /// Sets the requested state rather than toggling row existence. A multi can have
  /// cached this subreddit without the account being subscribed to it. Existing
  /// metadata (including a newer favorite) is not replaced by the caller's snapshot.
  @discardableResult
  func setSubscription(_ subscribed: Bool, subreddit: SubredditData, expecting expected: Bool? = nil) async -> Bool {
    await transaction(fullname: subreddit.name) { context in
      let request = requestForSubreddit(credential.id, fullname: subreddit.name)
      let existing = try context.fetch(request)
      if let expected, existing.contains(where: \.user_is_subscriber) != expected {
        return false
      }
      if subscribed {
        var data = subreddit
        data.user_is_subscriber = true
        if existing.isEmpty {
          _ = CachedSub(data: data, context: context, credentialID: credential.id)
        } else {
          for sub in existing {
            sub.user_is_subscriber = true
          }
        }
      } else {
        for sub in existing {
          if sub.multis?.isEmpty == false {
            sub.user_is_subscriber = false
          } else {
            context.delete(sub)
          }
        }
      }
      return true
    }
  }

  /// Only existing rows are favorited. Failure rollback is conditional so it does
  /// not blindly overwrite a newer local toggle or recreate an unsubscribed row.
  @discardableResult
  func setFavorite(_ favorited: Bool, fullname: String, expecting expected: Bool? = nil) async -> Bool {
    await transaction(fullname: fullname) { context in
      let existing = try context.fetch(requestForSubreddit(credential.id, fullname: fullname))
      guard !existing.isEmpty else { return false }
      if let expected, !existing.allSatisfy({ $0.user_has_favorited == expected }) {
        return false
      }
      for sub in existing {
        sub.user_has_favorited = favorited
      }
      return true
    }
  }

  /// All bulk snapshots share one private queue, including their reads and updates.
  /// Parallel network fetches cannot reconcile the same missing row concurrently.
  /// Only the final validation/save
  /// takes the credential owner's lease, which serializes grant invalidation.
  private func bulkTransaction(_ update: @escaping @Sendable (NSManagedObjectContext) throws -> Bool) async -> Bool {
    let context = context ?? PersistenceController.shared.accountListsContext
    let manager = credentialsManager
    let authorization = authorization
    let beforeCommit = beforeBulkCommit
    return await context.perform {
      guard manager.containsAuthorization(authorization) else { return false }
      do {
        guard try update(context) else { return false }
        beforeCommit?()
        let saved = try manager.withCurrentAuthorization(authorization) {
          try context.save()
          return true
        }
        if saved == nil {
          context.rollback()
        }
        return saved ?? false
      } catch {
        context.rollback()
        Logger(subsystem: "com.sertacozercan.helio", category: "AccountListPersistence")
          .error("Failed to persist account lists: \(error.localizedDescription)")
        return false
      }
    }
  }

  /// The save notification is consumed only by Core Data's cross-context merge API.
  private struct LocalWriteResult: @unchecked Sendable {
    let succeeded: Bool
    let notification: Notification?
  }

  private func transaction(fullname: String, _ update: @escaping @Sendable (NSManagedObjectContext) throws -> Bool) async -> Bool {
    let source = context ?? PersistenceController.shared.accountListsContext
    let manager = credentialsManager
    let authorization = authorization
    let revisions = Self.stateRevisions
    // Queue the entire local transaction behind bulk reconciliation, not only its save.
    // The isolated writer protects unrelated pending edits in an injected/shared context.
    let result = await source.perform {
      guard manager.containsAuthorization(authorization), let coordinator = source.persistentStoreCoordinator else {
        return LocalWriteResult(succeeded: false, notification: nil)
      }
      let writer = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
      writer.persistentStoreCoordinator = coordinator
      writer.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
      let result = writer.performAndWait {
        let saved = Mutex<Notification?>(nil)
        let observer = NotificationCenter.default.addObserver(forName: .NSManagedObjectContextDidSave, object: writer, queue: nil) { notification in
          saved.withLock { $0 = notification }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        do {
          guard try update(writer) else { return LocalWriteResult(succeeded: false, notification: nil) }
          let accepted = try manager.withCurrentAuthorization(authorization) {
            try writer.save()
            revisions.value.withLock { state in
              state.revision += 1
              state.rows[authorization, default: [:]][fullname] = state.revision
            }
            return true
          }
          guard accepted == true else {
            writer.rollback()
            return LocalWriteResult(succeeded: false, notification: nil)
          }
          return LocalWriteResult(succeeded: true, notification: saved.withLock { $0 })
        } catch {
          writer.rollback()
          Logger(subsystem: "com.sertacozercan.helio", category: "AccountListPersistence")
            .error("Failed to persist account lists: \(error.localizedDescription)")
          return LocalWriteResult(succeeded: false, notification: nil)
        }
      }
      if let notification = result.notification {
        source.mergeChanges(fromContextDidSave: notification)
      }
      return result
    }
    if context == nil, let notification = result.notification {
      let view = PersistenceController.shared.container.viewContext
      await view.perform { view.mergeChanges(fromContextDidSave: notification) }
    }
    return result.succeeded
  }
}

private func predicateForAccount(_ credentialID: UUID) -> NSPredicate {
  NSPredicate(format: "helioCredentialID == %@", credentialID as CVarArg)
}

private func requestForSubreddit(_ credentialID: UUID, fullname: String) -> NSFetchRequest<CachedSub> {
  let request = CachedSub.fetchRequest()
  request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicateForAccount(credentialID), NSPredicate(format: "uuid == %@", fullname)])
  return request
}
