//
//  RedditInfoLoader.swift
//  Helio
//

import Alamofire
import Foundation

/// Loads posts, comments and subreddits through `/api/info`, which takes up to 100 of them per
/// request. Lookups made together (the reddit links in a feed page, the same link laid out twice)
/// share one request, and results are kept for a few minutes.
///
/// Everything is per account: results carry the account's votes, saves and subscriptions, and
/// only some accounts can see a private subreddit. Each request is made as the account that asked.
actor RedditInfoLoader {
  static let shared = RedditInfoLoader()

  static let batchSize = 100
  static let coalesceDelay: Duration = .milliseconds(30)
  static let maxAge: TimeInterval = 5 * 60

  enum Thing: Sendable {
    case post(PostData)
    case comment(CommentData)
    case subreddit(SubredditData)
  }

  /// A fullname (`t3_abc`) or a subreddit name (lowercased).
  enum Target: Hashable, Sendable {
    case fullname(String)
    case subredditName(String)
  }

  struct Key: Hashable, Sendable {
    let account: UUID?
    let target: Target
  }

  typealias Fetch = @Sendable (_ fullnames: [String], _ subredditNames: [String], _ account: RedditCredential?) async -> [Thing]?

  private let fetch: Fetch
  private let currentAccount: @Sendable () -> RedditCredential?
  private var cache: [Key: (thing: Thing, date: Date)] = [:]
  private var pending: Set<Key> = []
  private var accounts: [UUID: RedditCredential] = [:]
  private var flush: Task<Void, Never>?
  private var inFlight: [Key: Task<Void, Never>] = [:]

  init(
    currentAccount: @escaping @Sendable () -> RedditCredential? = { RedditCredentialsManager.shared.selectedCredential },
    fetch: @escaping Fetch = { fullnames, names, account in
      await RedditAPI.shared.fetchInfoThings(fullnames: fullnames, subredditNames: names, account: account)
    },
  ) {
    self.currentAccount = currentAccount
    self.fetch = fetch
  }

  func post(_ fullname: String) async -> PostData? {
    if case let .post(data) = await thing(.fullname(fullname)) {
      data
    } else {
      nil
    }
  }

  func comment(_ fullname: String) async -> CommentData? {
    if case let .comment(data) = await thing(.fullname(fullname)) {
      data
    } else {
      nil
    }
  }

  func subreddit(named name: String) async -> SubredditData? {
    if case let .subreddit(data) = await thing(.subredditName(name.lowercased())) {
      data
    } else {
      nil
    }
  }

  func thing(_ target: Target) async -> Thing? {
    let account = currentAccount()
    let key = Key(account: account?.id, target: target)
    if let cached = cache[key], Date().timeIntervalSince(cached.date) < Self.maxAge {
      return cached.thing
    }
    if inFlight[key] == nil {
      if let account {
        accounts[account.id] = account
      }
      pending.insert(key)
      let flush = flush ?? Task {
        try? await Task.sleep(for: Self.coalesceDelay)
        await self.sendPending()
      }
      self.flush = flush
      inFlight[key] = flush
    }
    await inFlight[key]?.value
    return cache[key]?.thing
  }

  private func sendPending() async {
    let keys = Array(pending)
    pending = []
    flush = nil
    func batches(_ list: [String]) -> [[String]] {
      stride(from: 0, to: list.count, by: Self.batchSize).map { Array(list[$0 ..< min($0 + Self.batchSize, list.count)]) }
    }
    struct Request {
      let account: UUID?
      let fullnames: [String]
      let names: [String]
    }
    var requests: [Request] = []
    for (account, accountKeys) in Dictionary(grouping: keys, by: \.account) {
      var fullnames: [String] = []
      var names: [String] = []
      for key in accountKeys {
        switch key.target {
        case let .fullname(fullname): fullnames.append(fullname)
        case let .subredditName(name): names.append(name)
        }
      }
      requests += batches(fullnames).map { Request(account: account, fullnames: $0, names: []) }
        + batches(names).map { Request(account: account, fullnames: [], names: $0) }
    }
    let accounts = accounts
    let results = await withTaskGroup(of: (UUID?, [Thing]).self) { group in
      for request in requests {
        let credential = request.account.flatMap { accounts[$0] }
        group.addTask { [fetch] in await (request.account, fetch(request.fullnames, request.names, credential) ?? []) }
      }
      return await group.reduce(into: []) { $0.append($1) }
    }
    let now = Date()
    for (account, things) in results {
      for thing in things {
        for target in Self.targets(of: thing) {
          cache[Key(account: account, target: target)] = (thing, now)
        }
      }
    }
    for key in keys {
      inFlight[key] = nil
    }
  }

  static func targets(of thing: Thing) -> [Target] {
    switch thing {
    case let .post(data): [.fullname("t3_\(data.id)")]
    case let .comment(data): [.fullname("t1_\(data.id)")]
    case let .subreddit(data): [.fullname(data.name), .subredditName((data.display_name ?? "").lowercased())]
    }
  }
}

extension RedditAPI {
  /// `/api/info` for fullnames or for subreddit names (Reddit takes one or the other), as `account`
  /// (the selected account when nil).
  func fetchInfoThings(fullnames: [String], subredditNames: [String], account: RedditCredential?) async -> [RedditInfoLoader.Thing]? {
    let params = subredditNames.isEmpty ? FetchInfoThingsPayload(id: fullnames.joined(separator: ",")) : FetchInfoThingsPayload(sr_name: subredditNames.joined(separator: ","))
    switch await self.doRequest("\(RedditAPI.redditApiURLBase)/api/info", method: .get, params: params, paramsLocation: .queryString, decodable: InfoListing.self, altCredential: account) {
    case let .success(listing):
      return listing.data?.children?.compactMap(\.thing)
    case .failure:
      return nil
    }
  }

  struct FetchInfoThingsPayload: Codable {
    var id: String?
    var sr_name: String?
    var raw_json = 1
  }

  struct InfoListing: Decodable {
    struct Children: Decodable {
      let children: [Child]?
    }

    /// A child Helio can't decode is skipped rather than failing the whole listing.
    struct Child: Decodable {
      let thing: RedditInfoLoader.Thing?

      enum CodingKeys: CodingKey { case kind, data }

      init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        thing = switch try? container.decode(String.self, forKey: .kind) {
        case "t3": (try? container.decode(PostData.self, forKey: .data)).map { .post($0) }
        case "t1": (try? container.decode(CommentData.self, forKey: .data)).map { .comment($0) }
        case "t5": (try? container.decode(SubredditData.self, forKey: .data)).map { .subreddit($0) }
        default: nil
        }
      }
    }

    let data: Children?
  }
}
