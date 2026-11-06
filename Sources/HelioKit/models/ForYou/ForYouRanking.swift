//
//  ForYouRanking.swift
//  Helio
//

import Foundation

/// Why For You suggests a subreddit, shown in a suggested post's menu.
enum ForYouReason: Hashable, Sendable {
  /// A subreddit you follow lists it as a related community.
  case related(to: String)
  case upvoted
  case saved
  /// A post from it was crossposted into a subreddit you follow.
  case crossposted(into: String)

  var text: String {
    switch self {
    case let .related(seed): "Similar to r/\(seed)"
    case .upvoted: "You upvoted posts from here"
    case .saved: "You saved posts from here"
    case let .crossposted(sub): "Crossposted to r/\(sub)"
    }
  }
}

struct ForYouCandidate: Hashable, Sendable {
  let name: String
  let score: Double
  let reason: ForYouReason
}

/// A community a subreddit's sidebar lists as related.
struct ForYouRelatedSub: Hashable, Sendable {
  let name: String
  let subscribers: Int?
  let over18: Bool
}

/// What the account did that hints at subreddits it doesn't follow yet. Names in any case.
struct ForYouSignals: Sendable {
  struct Related: Sendable {
    let seed: String
    let sub: ForYouRelatedSub
  }

  struct Crosspost: Sendable {
    let from: String
    let into: String
  }

  /// Lowercased names of the subreddits the account follows.
  var subscribed: Set<String> = []
  /// Lowercased names never to suggest: dismissed and filtered subreddits.
  var excluded: Set<String> = []
  /// The subreddit of each upvoted post.
  var upvoted: [String] = []
  /// The subreddit of each saved post or comment.
  var saved: [String] = []
  var related: [Related] = []
  var crossposts: [Crosspost] = []
}

enum ForYouRanking {
  /// Related communities this small are usually inactive.
  static let minRelatedSubscribers = 1000

  /// Subreddits to suggest, strongest first. Several kinds of signal add up, each capped so one
  /// binge of upvotes in a sub doesn't outweigh everything else.
  static func candidates(from signals: ForYouSignals, limit: Int = 15) -> [ForYouCandidate] {
    struct Tally {
      var name: String
      var upvoted = 0
      var saved = 0
      var relatedSeeds: [String] = []
      var crosspostedInto: [String] = []
    }
    var tallies: [String: Tally] = [:]
    func record(_ name: String, _ update: (inout Tally) -> Void) {
      let key = name.lowercased()
      guard !key.isEmpty, !key.hasPrefix("u_"), !builtInFeedIDs.contains(key),
            !signals.subscribed.contains(key), !signals.excluded.contains(key) else { return }
      update(&tallies[key, default: Tally(name: name)])
    }

    for sub in signals.upvoted {
      record(sub) { $0.upvoted += 1 }
    }
    for sub in signals.saved {
      record(sub) { $0.saved += 1 }
    }
    for related in signals.related where !related.sub.over18 && (related.sub.subscribers ?? minRelatedSubscribers) >= minRelatedSubscribers {
      record(related.sub.name) { tally in
        if !tally.relatedSeeds.contains(where: { $0.caseInsensitiveCompare(related.seed) == .orderedSame }) {
          tally.relatedSeeds.append(related.seed)
        }
      }
    }
    for crosspost in signals.crossposts {
      record(crosspost.from) { $0.crosspostedInto.append(crosspost.into) }
    }

    let ranked = tallies.values.map { tally -> ForYouCandidate in
      // In order of preference when two kinds weigh the same.
      let parts: [(Double, ForYouReason?)] = [
        (Double(min(tally.saved, 5)) * 1.5, .saved),
        (Double(min(tally.relatedSeeds.count, 3)) * 2, tally.relatedSeeds.first.map { .related(to: $0) }),
        (Double(min(tally.upvoted, 5)), .upvoted),
        (Double(min(tally.crosspostedInto.count, 4)), tally.crosspostedInto.first.map { .crossposted(into: $0) }),
      ]
      let score = parts.reduce(0) { $0 + $1.0 }
      let strongest = parts.filter { $0.1 != nil }.max { $0.0 < $1.0 }
      return ForYouCandidate(name: tally.name, score: score, reason: strongest?.1 ?? .upvoted)
    }
    return Array(ranked.sorted { $0.score != $1.score ? $0.score > $1.score : $0.name.lowercased() < $1.name.lowercased() }.prefix(limit))
  }

  /// Followed subreddits to look up related communities for: the ones the account upvotes in
  /// most, then the ones its Home shows most.
  static func seeds(upvoted: [String], home: [String], subscribed: Set<String>, count: Int = 5) -> [String] {
    struct Tally {
      let name: String
      var count = 0
      let first: Int
    }
    var seen: Set<String> = []
    var seeds: [String] = []
    for subs in [upvoted, home] {
      var counts: [String: Tally] = [:]
      for (index, sub) in subs.enumerated() {
        let key = sub.lowercased()
        guard subscribed.contains(key), !seen.contains(key) else { continue }
        counts[key, default: Tally(name: sub, first: index)].count += 1
      }
      let ordered = counts.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.first < $1.first }
      for entry in ordered where seeds.count < count {
        seen.insert(entry.name.lowercased())
        seeds.append(entry.name)
      }
    }
    return seeds
  }

  /// Up to `count` items, best scored first, at most `perSub` from one subreddit. Items without
  /// a score keep their order after the scored ones.
  static func pick<T>(_ items: [T], count: Int, perSub: Int = 2, sub: (T) -> String, score: (T) -> Double?) -> [T] {
    let ordered = items.enumerated().sorted { lhs, rhs in
      switch (score(lhs.element), score(rhs.element)) {
      case let (left?, right?) where left != right: left > right
      case (.some, nil): true
      case (nil, .some): false
      default: lhs.offset < rhs.offset
      }
    }
    var perSubCount: [String: Int] = [:]
    var picked: [T] = []
    for (_, item) in ordered where picked.count < count {
      let key = sub(item).lowercased()
      guard perSubCount[key, default: 0] < perSub else { continue }
      perSubCount[key, default: 0] += 1
      picked.append(item)
    }
    return picked
  }

  /// `base` with one of `extra` after every `every` items. With no `base`, all of `extra`.
  static func interleave<T>(_ base: [T], _ extra: [T], every: Int) -> [T] {
    guard !base.isEmpty else { return extra }
    var extras = extra.makeIterator()
    var result: [T] = []
    result.reserveCapacity(base.count + extra.count)
    for (index, item) in base.enumerated() {
      result.append(item)
      if (index + 1) % every == 0, let next = extras.next() {
        result.append(next)
      }
    }
    return result
  }
}

/// Where a For You page chain is in each of its two listings: Home and the suggested
/// subreddits, whose multireddit it keeps, as Reddit's cursor only holds for the same listing.
/// Carried through the feed as its opaque `after`.
struct ForYouCursor: Codable, Equatable {
  /// nil once Home ran out.
  var home: String?
  /// nil once the suggestions ran out, or when there were none.
  var suggested: String?
  var subs: [String]

  private static let prefix = "foryou:"

  /// nil when both listings ran out: the end of the feed.
  var encoded: String? {
    guard home != nil || (suggested != nil && !subs.isEmpty), let json = try? JSONEncoder().encode(self) else { return nil }
    return Self.prefix + json.base64EncodedString()
  }

  init(home: String?, suggested: String?, subs: [String]) {
    self.home = home
    self.suggested = suggested
    self.subs = subs
  }

  init?(encoded: String) {
    guard encoded.hasPrefix(Self.prefix), let data = Data(base64Encoded: String(encoded.dropFirst(Self.prefix.count))),
          let cursor = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
    self = cursor
  }
}
