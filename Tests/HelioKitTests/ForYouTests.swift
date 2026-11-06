import Foundation
import Synchronization
import Testing
@testable import HelioKit

struct ForYouRankingTests {
  @Test func addsUpSignalsAndLeavesOutFollowedAndExcludedSubreddits() {
    let signals = ForYouSignals(
      subscribed: ["homelab"],
      excluded: ["dismissed"],
      upvoted: ["selfhosted", "selfhosted", "MechanicalKeyboards", "homelab", "u_someone", "Dismissed"],
      saved: ["espresso"],
      related: [
        .init(seed: "homelab", sub: ForYouRelatedSub(name: "selfhosted", subscribers: 500_000, over18: false)),
        .init(seed: "homelab", sub: ForYouRelatedSub(name: "TinySub", subscribers: 12, over18: false)),
        .init(seed: "homelab", sub: ForYouRelatedSub(name: "AdultSub", subscribers: 90000, over18: true)),
      ],
      crossposts: [.init(from: "DataHoarder", into: "homelab")],
    )

    let candidates = ForYouRanking.candidates(from: signals)

    // selfhosted: 2 upvotes and a related listing, 4; espresso: a save, 1.5; then 1 each, by name.
    #expect(candidates.map(\.name) == ["selfhosted", "espresso", "DataHoarder", "MechanicalKeyboards"])
    #expect(candidates.first?.score == 4)
    #expect(candidates.first?.reason == .related(to: "homelab"))
    #expect(candidates.first { $0.name == "espresso" }?.reason == .saved)
    #expect(candidates.first { $0.name == "DataHoarder" }?.reason == .crossposted(into: "homelab"))
  }

  @Test func capsEachKindOfSignal() {
    let binge = ForYouSignals(upvoted: Array(repeating: "binge", count: 40), saved: ["a", "a", "b", "b"])
    let candidates = ForYouRanking.candidates(from: binge)
    #expect(candidates.first { $0.name == "binge" }?.score == 5)
  }

  @Test func seedsAreFollowedSubsUpvotedMostThenHomes() {
    let seeds = ForYouRanking.seeds(
      upvoted: ["Coffee", "notfollowed", "swift", "swift"],
      home: ["homelab", "homelab", "swift", "pics"],
      subscribed: ["coffee", "swift", "homelab", "pics"],
      count: 3,
    )
    #expect(seeds == ["swift", "Coffee", "homelab"])
  }

  @Test func picksBestScoredWithAFewPerSubreddit() {
    let items = [("a", 0.1), ("a", 0.9), ("a", 0.8), ("b", 0.2), ("c", nil), ("a", 0.7)] as [(String, Double?)]
    let picked = ForYouRanking.pick(items, count: 4, perSub: 2, sub: \.0, score: \.1)
    #expect(picked.map(\.0) == ["a", "a", "b", "c"])
    #expect(picked.map(\.1) == [0.9, 0.8, 0.2, nil])
  }

  @Test func interleavesOneAfterEveryFew() {
    #expect(ForYouRanking.interleave([1, 2, 3, 4, 5, 6, 7, 8, 9], [100, 200, 300], every: 4) == [1, 2, 3, 4, 100, 5, 6, 7, 8, 200, 9])
    #expect(ForYouRanking.interleave([], [100, 200], every: 4) == [100, 200])
  }

  @Test func cursorRoundTripsAndEndsWithBothListings() throws {
    let cursor = ForYouCursor(home: "t3_home", suggested: "t3_sugg", subs: ["selfhosted", "espresso"])
    let encoded = try #require(cursor.encoded)
    #expect(ForYouCursor(encoded: encoded) == cursor)
    #expect(ForYouCursor(encoded: "t3_abc") == nil)
    #expect(ForYouCursor(home: nil, suggested: "t3_sugg", subs: ["a"]).encoded != nil)
    #expect(ForYouCursor(home: nil, suggested: "t3_sugg", subs: []).encoded == nil)
    #expect(ForYouCursor(home: nil, suggested: nil, subs: ["a"]).encoded == nil)
  }

  @Test func readsCommunityListsOutOfASubredditsWidgets() throws {
    let json = """
    {"items": {
      "widget_1": {"kind": "community-list", "shortName": "Related", "data": [
        {"name": "selfhosted", "subscribers": 500000, "isNSFW": false, "type": "subreddit"},
        {"subscribers": 3},
        {"name": "AdultSub", "subscribers": 9000, "isNSFW": true}
      ]},
      "widget_2": {"kind": "image", "data": [{"url": "https://example.com/a.png", "width": 1, "height": 1}]},
      "widget_3": {"kind": "textarea", "text": "Hello"},
      "widget_4": {"kind": "community-list", "data": "unexpected"}
    }, "layout": {}}
    """
    let widgets = try JSONDecoder().decode(SubredditWidgets.self, from: Data(json.utf8))
    let related = widgets.items.values.flatMap(\.communities)
    #expect(Set(related) == [
      ForYouRelatedSub(name: "selfhosted", subscribers: 500_000, over18: false),
      ForYouRelatedSub(name: "AdultSub", subscribers: 9000, over18: true),
    ])
  }
}

struct ForYouEngineTests {
  private static let credential = RedditCredential(apiAppID: "placeholder-client-id", accessToken: "placeholder-access-token", refreshToken: "placeholder-grant", expiration: 3600, lastRefresh: Date(), userName: "placeholder_user")

  private static func post(_ id: String, sub: String, title: String = "A post", over18: Bool = false) -> PostData {
    guard let encoded = try? JSONEncoder().encode(postSampleData),
          var json = (try? JSONSerialization.jsonObject(with: encoded)) as? [String: Any]
    else { fatalError("The sample post doesn't encode") }
    json["id"] = id
    json["name"] = "t3_\(id)"
    json["subreddit"] = sub
    json["title"] = title
    json["over_18"] = over18
    json["stickied"] = false
    json["crosspost_parent_list"] = nil
    guard let data = try? JSONSerialization.data(withJSONObject: json), let post = try? JSONDecoder().decode(PostData.self, from: data)
    else { fatalError("The sample post doesn't decode") }
    return post
  }

  private final class Calls: Sendable {
    let home = Mutex<[String?]>([])
    let suggestions = Mutex<[([String], String?)]>([])
    let upvoted = Mutex(0)
  }

  private func engine(
    calls: Calls,
    homeFails: Bool = false,
    suggestionsFail: Bool = false,
    homeAfter: String? = "t3_h8",
    suggestionPage: (@Sendable (_ after: String?) -> ([PostData], String?)?)? = nil,
  ) -> ForYouEngine {
    let sources = ForYouSources(
      home: { _, after, _, _ in
        calls.home.withLock { $0.append(after) }
        guard !homeFails else { return nil }
        let posts = (1 ... 8).map { Self.post("h\($0)\(after ?? "")", sub: "homelab") }
        return (posts, after == nil ? homeAfter : nil)
      },
      suggestions: { subs, after, _, _ in
        calls.suggestions.withLock { $0.append((subs, after)) }
        if let suggestionPage {
          return suggestionPage(after)
        }
        guard !suggestionsFail else { return nil }
        return ([
          Self.post("s1\(after ?? "")", sub: "selfhosted", title: "My new home server rack"),
          Self.post("s2\(after ?? "")", sub: "espresso", title: "Dialing in a new grinder"),
          Self.post("s3\(after ?? "")", sub: "selfhosted", title: "NSFW thing", over18: true),
          Self.post("s4\(after ?? "")", sub: "homelab", title: "Followed already"),
        ], after == nil ? "t3_s4" : nil)
      },
      upvoted: { _, _ in
        calls.upvoted.withLock { $0 += 1 }
        return [Self.post("u1", sub: "selfhosted", title: "Proxmox cluster tips"), Self.post("u2", sub: "espresso", title: "Espresso puck prep")]
      },
      saved: { _, _ in [] },
      related: { _, _ in [] },
      subscribed: { _ in ["homelab"] },
      excluded: { [] },
    )
    return ForYouEngine(sources: sources)
  }

  @Test func mixesOneSuggestionAfterEveryFourHomePosts() async throws {
    let calls = Calls()
    let page = try #require(await engine(calls: calls).page(after: nil, sort: .best, limit: 8, credential: Self.credential))

    let subs = page.posts.map(\.subreddit)
    #expect(subs.count == 10)
    #expect(subs[0 ..< 4].allSatisfy { $0 == "homelab" })
    #expect(subs[4] != "homelab")
    #expect(subs[9] != "homelab")
    // The followed sub's post and the NSFW one are never suggested.
    #expect(Set(page.reasons.keys) == ["t3_s1", "t3_s2"])
    #expect(page.reasons["t3_s1"] == .upvoted)

    let cursor = try #require(page.after.flatMap(ForYouCursor.init(encoded:)))
    #expect(cursor.home == "t3_h8")
    #expect(cursor.suggested == "t3_s4")
    #expect(Set(cursor.subs) == ["selfhosted", "espresso"])
  }

  @Test func nextPagesFollowBothCursorsAndReuseTheProfile() async throws {
    let calls = Calls()
    let engine = engine(calls: calls)
    let first = try #require(await engine.page(after: nil, sort: .best, limit: 8, credential: Self.credential))
    let second = try #require(await engine.page(after: first.after, sort: .best, limit: 8, credential: Self.credential))

    #expect(calls.home.withLock { $0 } == [nil, "t3_h8"])
    #expect(calls.suggestions.withLock { $0.map(\.1) } == [nil, "t3_s4"])
    #expect(calls.upvoted.withLock { $0 } == 1)
    #expect(second.reasons.count == 2)
    // Both listings ran out.
    #expect(second.after == nil)

    _ = await engine.page(after: nil, sort: .best, limit: 8, credential: Self.credential)
    #expect(calls.upvoted.withLock { $0 } == 1)
  }

  @Test func suggestionsCarryOnOnceHomeRunsOut() async throws {
    let calls = Calls()
    let engine = engine(calls: calls, homeAfter: nil)
    let page = try #require(await engine.page(after: nil, sort: .best, limit: 8, credential: Self.credential))
    let cursor = try #require(page.after.flatMap(ForYouCursor.init(encoded:)))
    #expect(cursor.home == nil)

    let next = try #require(await engine.page(after: page.after, sort: .best, limit: 8, credential: Self.credential))
    #expect(calls.home.withLock { $0 } == [nil])
    #expect(next.posts.map(\.name) == ["t3_s1t3_s4", "t3_s2t3_s4"] || next.posts.map(\.name) == ["t3_s2t3_s4", "t3_s1t3_s4"])
    #expect(next.reasons.count == 2)
    #expect(next.after == nil)
  }

  @Test func onceHomeRunsOutPagesOfOnlyFilteredSuggestionsAreSkipped() async throws {
    let calls = Calls()
    let engine = engine(calls: calls, homeAfter: nil) { after in
      switch after {
      case nil: ([Self.post("s1", sub: "selfhosted")], "t3_p1")
      case "t3_p1": ([Self.post("nsfw", sub: "selfhosted", over18: true), Self.post("followed", sub: "homelab")], "t3_p2")
      default: ([Self.post("late", sub: "espresso")], nil)
      }
    }
    let first = try #require(await engine.page(after: nil, sort: .best, limit: 8, credential: Self.credential))
    let next = try #require(await engine.page(after: first.after, sort: .best, limit: 8, credential: Self.credential))
    #expect(next.posts.map(\.name) == ["t3_late"])
    #expect(next.after == nil)
    #expect(calls.suggestions.withLock { $0.map(\.1) } == [nil, "t3_p1", "t3_p2"])
  }

  @Test func onceHomeRunsOutSuggestionsFailingFailsThePage() async throws {
    let calls = Calls()
    let engine = engine(calls: calls, homeAfter: nil) { after in
      after == nil ? ([Self.post("s1", sub: "selfhosted")], "t3_p1") : nil
    }
    let first = try #require(await engine.page(after: nil, sort: .best, limit: 8, credential: Self.credential))
    let next = await engine.page(after: first.after, sort: .best, limit: 8, credential: Self.credential)
    #expect(next == nil)
  }

  @Test func homeFailingFailsThePage() async {
    let calls = Calls()
    let page = await engine(calls: calls, homeFails: true).page(after: nil, sort: .best, limit: 8, credential: Self.credential)
    #expect(page == nil)
  }

  @Test func suggestionsFailingLeavesHome() async throws {
    let calls = Calls()
    let page = try #require(await engine(calls: calls, suggestionsFail: true).page(after: nil, sort: .best, limit: 8, credential: Self.credential))
    #expect(page.posts.count == 8)
    #expect(page.reasons.isEmpty)
    let cursor = try #require(page.after.flatMap(ForYouCursor.init(encoded:)))
    #expect(cursor.suggested == nil)
  }

  @Test func dismissedSubredditsStopBeingSuggested() async throws {
    let calls = Calls()
    let engine = engine(calls: calls)
    let first = try #require(await engine.page(after: nil, sort: .best, limit: 8, credential: Self.credential))
    await engine.dismiss("Espresso")
    let second = try #require(await engine.page(after: first.after, sort: .best, limit: 8, credential: Self.credential))
    #expect(Set(second.posts.filter { second.reasons[$0.name] != nil }.map(\.subreddit)) == ["selfhosted"])
  }
}

struct InterestScorerTests {
  @Test func scoresTitlesNearLikedOnesHigher() throws {
    // The English sentence embedding ships with the OS; skip where it's missing.
    guard let scorer = InterestScorer(likedTitles: ["Building a home server rack with Proxmox", "My espresso machine setup"]) else { return }
    let near = try #require(scorer.score("Upgraded my home server with more storage"))
    let far = try #require(scorer.score("The election results are in"))
    #expect(near > far)
  }
}
