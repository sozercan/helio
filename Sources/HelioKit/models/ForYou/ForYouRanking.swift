//
//  ForYouRanking.swift
//  Helio
//

import Foundation

/// Why For You suggests a subreddit, shown in a suggested post's menu.
enum ForYouReason: Codable, Hashable, Sendable {
  /// A subreddit you follow lists it as a related community.
  case related(to: String)
  case upvoted
  case saved
  /// A post from it was crossposted into a subreddit you follow.
  case crossposted(into: String)

  var text: String {
    switch self {
    case let .related(seed): "Similar to r/\(seed)"
    case .upvoted: "From posts you upvoted"
    case .saved: "From things you saved"
    case let .crossposted(sub): "Crossposted to r/\(sub)"
    }
  }
}

struct ForYouCandidate: Hashable, Sendable {
  /// The signals behind a candidate. Upvotes and saves count recent ones only.
  struct Breakdown: Hashable, Sendable {
    var upvoted = 0
    var saved = 0
    var relatedTo: [String] = []
    var crossposted: [String] = []

    var summary: String {
      var parts: [String] = []
      if upvoted > 0 {
        parts.append(upvoted == 1 ? "1 upvote" : "\(upvoted) upvotes")
      }
      if saved > 0 {
        parts.append(saved == 1 ? "1 save" : "\(saved) saves")
      }
      if !relatedTo.isEmpty {
        parts.append("related to " + relatedTo.map { "r/\($0)" }.joined(separator: ", "))
      }
      if !crossposted.isEmpty {
        parts.append(crossposted.count == 1 ? "1 crosspost" : "\(crossposted.count) crossposts")
      }
      return parts.joined(separator: " · ")
    }
  }

  let name: String
  let score: Double
  let reason: ForYouReason
  var breakdown = Breakdown()
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
  /// The subreddit of each upvoted post, most recently upvoted first.
  var upvoted: [String] = []
  /// The subreddit of each saved post or comment, most recently saved first.
  var saved: [String] = []
  var related: [Related] = []
  var crossposts: [Crosspost] = []
}

enum ForYouRanking {
  /// Related communities this small are usually inactive.
  static let minRelatedSubscribers = 1000

  /// Upvotes and saves past this many, counted from the latest, are too old to say much.
  static let recentItems = 50
  /// A sub needs this many upvotes, saves and crossposts between them, unless a subreddit you
  /// follow lists it as related: one stray upvote or old save isn't an interest.
  static let minWeakSignals = 2

  /// How much an upvote or save counts by how recent it is: Reddit lists them newest first.
  static func recencyWeight(_ index: Int) -> Double {
    index < recentItems / 2 ? 1 : index < recentItems ? 0.5 : 0
  }

  /// Subreddits to suggest, strongest first.
  static func candidates(from signals: ForYouSignals, limit: Int = 15) -> [ForYouCandidate] {
    Array(ranked(from: signals).qualified.prefix(limit))
  }

  /// Every subreddit the signals point at, strongest first: the ones with enough signal to
  /// suggest, and the ones without. Several kinds of signal add up, each capped so one binge
  /// in a sub doesn't outweigh everything else.
  static func ranked(from signals: ForYouSignals) -> (qualified: [ForYouCandidate], unqualified: [ForYouCandidate]) {
    struct Tally {
      var name: String
      var upvoted = 0.0
      var saved = 0.0
      var breakdown = ForYouCandidate.Breakdown()
    }
    var tallies: [String: Tally] = [:]
    func record(_ name: String, _ update: (inout Tally) -> Void) {
      let key = name.lowercased()
      guard !key.isEmpty, !key.hasPrefix("u_"), !builtInFeedIDs.contains(key),
            !signals.subscribed.contains(key), !signals.excluded.contains(key) else { return }
      update(&tallies[key, default: Tally(name: name)])
    }

    for (index, sub) in signals.upvoted.enumerated() where recencyWeight(index) > 0 {
      record(sub) { tally in
        tally.upvoted += recencyWeight(index)
        tally.breakdown.upvoted += 1
      }
    }
    for (index, sub) in signals.saved.enumerated() where recencyWeight(index) > 0 {
      record(sub) { tally in
        tally.saved += recencyWeight(index)
        tally.breakdown.saved += 1
      }
    }
    for related in signals.related where !related.sub.over18 && (related.sub.subscribers ?? minRelatedSubscribers) >= minRelatedSubscribers {
      record(related.sub.name) { tally in
        if !tally.breakdown.relatedTo.contains(where: { $0.caseInsensitiveCompare(related.seed) == .orderedSame }) {
          tally.breakdown.relatedTo.append(related.seed)
        }
      }
    }
    for crosspost in signals.crossposts {
      record(crosspost.from) { $0.breakdown.crossposted.append(crosspost.into) }
    }

    var qualified: [ForYouCandidate] = []
    var unqualified: [ForYouCandidate] = []
    for tally in tallies.values {
      let breakdown = tally.breakdown
      // In order of preference when two kinds weigh the same.
      let parts: [(Double, ForYouReason?)] = [
        (Double(min(breakdown.relatedTo.count, 3)) * 2, breakdown.relatedTo.first.map { .related(to: $0) }),
        (min(tally.saved, 5) * 1.5, breakdown.saved > 0 ? .saved : nil),
        (min(tally.upvoted, 5), breakdown.upvoted > 0 ? .upvoted : nil),
        (Double(min(breakdown.crossposted.count, 4)), breakdown.crossposted.first.map { .crossposted(into: $0) }),
      ]
      let score = parts.reduce(0) { $0 + $1.0 }
      let strongest = parts.filter { $0.1 != nil }.max { $0.0 < $1.0 }
      let candidate = ForYouCandidate(name: tally.name, score: score, reason: strongest?.1 ?? .upvoted, breakdown: breakdown)
      let weakSignals = breakdown.upvoted + breakdown.saved + breakdown.crossposted.count
      if !breakdown.relatedTo.isEmpty || weakSignals >= minWeakSignals {
        qualified.append(candidate)
      } else {
        unqualified.append(candidate)
      }
    }
    let order: (ForYouCandidate, ForYouCandidate) -> Bool = { $0.score != $1.score ? $0.score > $1.score : $0.name.lowercased() < $1.name.lowercased() }
    return (qualified.sorted(by: order), unqualified.sorted(by: order))
  }

  /// The score a suggested post's title has to reach: the median of Home's, so a suggestion is
  /// at least as close to what the account likes as a typical post from its own subreddits.
  static func relevanceThreshold(homeScores: [Double]) -> Double? {
    guard !homeScores.isEmpty else { return nil }
    let sorted = homeScores.sorted()
    let middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
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
/// It keeps why each was suggested too, so the chain stays the same when the suggestions are
/// worked out again elsewhere. Carried through the feed as its opaque `after`.
struct ForYouCursor: Codable, Equatable {
  /// nil once Home ran out.
  var home: String?
  /// nil once the suggestions ran out, or when there were none.
  var suggested: String?
  var subs: [String]
  /// By lowercased subreddit name.
  var reasons: [String: ForYouReason]

  private static let prefix = "foryou:"

  /// nil when both listings ran out: the end of the feed.
  var encoded: String? {
    guard home != nil || (suggested != nil && !subs.isEmpty), let json = try? JSONEncoder().encode(self) else { return nil }
    return Self.prefix + json.base64EncodedString()
  }

  init(home: String?, suggested: String?, subs: [String], reasons: [String: ForYouReason] = [:]) {
    self.home = home
    self.suggested = suggested
    self.subs = subs
    self.reasons = reasons
  }

  init?(encoded: String) {
    guard encoded.hasPrefix(Self.prefix), let data = Data(base64Encoded: String(encoded.dropFirst(Self.prefix.count))),
          let cursor = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
    self = cursor
  }
}
