import Foundation

actor AvatarLoader {
  static let shared = AvatarLoader()

  static let batchSize = 100
  static let coalesceDelay: Duration = .milliseconds(30)

  private let fetch: @Sendable ([String]) async -> [String: String?]?
  private var avatars: [String: URL] = [:]
  private var withoutAvatar: Set<String> = []
  private var pending: Set<String> = []
  private var flush: Task<Void, Never>?
  private var inFlight: [String: Task<Void, Never>] = [:]

  init(fetch: @escaping @Sendable ([String]) async -> [String: String?]? = { ids in
    let account = await MainActor.run {
      (id: RedditAPI.accountID(nil), authorization: RedditAPI.accountAuthorization(nil))
    }
    guard !RedditRateLimit.shared.isLow(account: account.id, authorization: account.authorization) else { return nil }
    return await RedditAPI.shared.fetchUsers(ids)?.mapValues(\.profile_img)
  }) {
    self.fetch = fetch
  }

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
