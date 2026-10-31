//
//  RedditInfoLoader.swift
//  Helio
//

import Alamofire
import Foundation

/// Loads posts, comments and subreddits through `/api/info`, which takes up to 100 of them per
/// request. Lookups made together (the reddit links in a feed page, the same link laid out twice)
/// share one request, and results are kept for a few minutes.
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

  /// A fullname (`t3_abc`) or a subreddit name (`r/apple`, lowercased).
  enum Key: Hashable, Sendable {
    case fullname(String)
    case subredditName(String)
  }

  private let fetch: @Sendable (_ fullnames: [String], _ subredditNames: [String]) async -> [Thing]?
  private var cache: [Key: (thing: Thing, date: Date)] = [:]
  private var pending: Set<Key> = []
  private var flush: Task<Void, Never>?
  private var inFlight: [Key: Task<Void, Never>] = [:]

  init(fetch: @escaping @Sendable (_ fullnames: [String], _ subredditNames: [String]) async -> [Thing]? = { fullnames, names in
    await RedditAPI.shared.fetchInfoThings(fullnames: fullnames, subredditNames: names)
  }) {
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

  func thing(_ key: Key) async -> Thing? {
    if let cached = cache[key], Date().timeIntervalSince(cached.date) < Self.maxAge {
      return cached.thing
    }
    if inFlight[key] == nil {
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
    var fullnames: [String] = []
    var names: [String] = []
    for key in keys {
      switch key {
      case let .fullname(fullname): fullnames.append(fullname)
      case let .subredditName(name): names.append(name)
      }
    }
    func batches(_ list: [String]) -> [[String]] {
      stride(from: 0, to: list.count, by: Self.batchSize).map { Array(list[$0 ..< min($0 + Self.batchSize, list.count)]) }
    }
    let requests = batches(fullnames).map { ($0, [String]()) } + batches(names).map { ([String](), $0) }
    let things = await withTaskGroup(of: [Thing].self) { group in
      for (ids, srNames) in requests {
        group.addTask { [fetch] in await fetch(ids, srNames) ?? [] }
      }
      return await group.reduce(into: []) { $0 += $1 }
    }
    let now = Date()
    for thing in things {
      for key in Self.keys(of: thing) {
        cache[key] = (thing, now)
      }
    }
    for key in keys {
      inFlight[key] = nil
    }
  }

  static func keys(of thing: Thing) -> [Key] {
    switch thing {
    case let .post(data): [.fullname("t3_\(data.id)")]
    case let .comment(data): [.fullname("t1_\(data.id)")]
    case let .subreddit(data): [.fullname(data.name), .subredditName((data.display_name ?? "").lowercased())]
    }
  }
}

extension RedditAPI {
  /// `/api/info` for fullnames or for subreddit names (Reddit takes one or the other).
  func fetchInfoThings(fullnames: [String], subredditNames: [String]) async -> [RedditInfoLoader.Thing]? {
    let params = subredditNames.isEmpty ? FetchInfoThingsPayload(id: fullnames.joined(separator: ",")) : FetchInfoThingsPayload(sr_name: subredditNames.joined(separator: ","))
    switch await self.doRequest("\(RedditAPI.redditApiURLBase)/api/info", method: .get, params: params, paramsLocation: .queryString, decodable: InfoListing.self) {
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
