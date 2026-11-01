//
//  AvatarLoader.swift
//  Helio
//

import Foundation

/// Looks up authors' avatars (`/api/user_data_by_account_ids`) once per session. The same
/// authors come back across feed pages, comment threads and crossposts, and lookups that arrive
/// together (a page's posts and its crossposts) go out as one request.
actor AvatarLoader {
  static let shared = AvatarLoader()

  /// Ids per request, Reddit's cap for fullname lists.
  static let batchSize = 100
  /// How long to wait for more lookups before sending a request.
  static let coalesceDelay: Duration = .milliseconds(30)

  private let fetch: @Sendable ([String]) async -> [String: String?]?
  private var avatars: [String: URL] = [:]
  private var withoutAvatar: Set<String> = []
  private var pending: Set<String> = []
  private var flush: Task<Void, Never>?
  private var inFlight: [String: Task<Void, Never>] = [:]

  /// `fetch` maps account fullnames to their profile image URL strings, nil on failure.
  init(fetch: @escaping @Sendable ([String]) async -> [String: String?]? = { ids in
    // Avatars are the first thing to go when the account's request budget runs low. A skipped
    // lookup counts as failed, so a later screen asks again.
    let account = await MainActor.run {
      (id: RedditAPI.accountID(nil), authorization: RedditAPI.accountAuthorization(nil))
    }
    guard !RedditRateLimit.shared.isLow(account: account.id, authorization: account.authorization) else { return nil }
    return await RedditAPI.shared.fetchUsers(ids)?.mapValues(\.profile_img)
  }) {
    self.fetch = fetch
  }

  /// Avatar URLs for the account fullnames that have one.
  func avatarURLs(for fullnames: [String]) async -> [String: URL] {
    let wanted = Set(fullnames)
    let missing = wanted.filter { avatars[$0] == nil && !withoutAvatar.contains($0) && inFlight[$0] == nil }
    if !missing.isEmpty {
      pending.formUnion(missing)
      let flush = flush ?? Task {
        try? await Task.sleep(for: Self.coalesceDelay)
        await self.sendPending()
      }
      self.flush = flush
      for name in missing {
        inFlight[name] = flush
      }
    }
    for task in Set(wanted.compactMap { inFlight[$0] }) {
      await task.value
    }
    return wanted.reduce(into: [:]) { result, name in result[name] = avatars[name] }
  }

  private func sendPending() async {
    let names = Array(pending)
    pending = []
    flush = nil
    let batches = stride(from: 0, to: names.count, by: Self.batchSize).map { Array(names[$0 ..< min($0 + Self.batchSize, names.count)]) }
    let results = await withTaskGroup(of: ([String], [String: String?]?).self) { group in
      for batch in batches {
        group.addTask { [fetch] in await (batch, fetch(batch)) }
      }
      return await group.reduce(into: []) { $0.append($1) }
    }
    for (batch, found) in results {
      // A failed request leaves its names unknown, so a later screen asks again.
      guard let found else { continue }
      for name in batch {
        if let urlStr = found[name].flatMap(\.self), let base = urlStr.split(separator: "?").first, let url = URL(string: String(base)) {
          avatars[name] = url
        } else {
          withoutAvatar.insert(name)
        }
      }
    }
    for name in names {
      inFlight[name] = nil
    }
  }
}
