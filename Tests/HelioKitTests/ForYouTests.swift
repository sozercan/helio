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

    let ranked = ForYouRanking.ranked(from: signals)

    // selfhosted: 2 upvotes and a related listing, 4. The rest have one weak signal each.
    #expect(ranked.qualified.map(\.name) == ["selfhosted"])
    #expect(ranked.qualified.first?.score == 4)
    #expect(ranked.qualified.first?.reason == .related(to: "homelab"))
    #expect(ranked.qualified.first?.breakdown == .init(upvoted: 2, relatedTo: ["homelab"]))
    #expect(ranked.unqualified.map(\.name) == ["espresso", "DataHoarder", "MechanicalKeyboards"])
    #expect(ranked.unqualified.first { $0.name == "espresso" }?.reason == .saved)
    #expect(ranked.unqualified.first { $0.name == "DataHoarder" }?.reason == .crossposted(into: "homelab"))
  }

  @Test func aRelatedListingAloneIsEnoughButOneUpvoteIsNot() {
    let signals = ForYouSignals(
      subscribed: ["homelab"],
      upvoted: ["canada"],
      saved: ["espresso", "espresso"],
      related: [.init(seed: "homelab", sub: ForYouRelatedSub(name: "selfhosted", subscribers: 500_000, over18: false))],
    )
    #expect(Set(ForYouRanking.candidates(from: signals).map(\.name)) == ["selfhosted", "espresso"])
  }

  @Test func aSubredditASidebarMarksNSFWIsNeverACandidate() {
    let signals = ForYouSignals(
      upvoted: ["AdultSub", "adultsub"],
      related: [.init(seed: "homelab", sub: ForYouRelatedSub(name: "AdultSub", subscribers: 90000, over18: true))],
    )
    let ranked = ForYouRanking.ranked(from: signals)
    #expect(ranked.qualified.isEmpty)
    #expect(ranked.unqualified.isEmpty)
  }

  @Test func olderUpvotesCountLessAndTheOldestNotAtAll() {
    let filler = (0 ..< 30).map { "filler\($0)" }
    let older = filler + ["older", "older"] + (0 ..< 20).map { "more\($0)" } + ["oldest", "oldest"]
    let ranked = ForYouRanking.ranked(from: ForYouSignals(upvoted: older))
    #expect(ranked.qualified.first { $0.name == "older" }?.score == 1)
    #expect(!(ranked.qualified + ranked.unqualified).contains { $0.name == "oldest" })
  }

  @Test func commentsPostsAndReadsAreSignalsTooButOneIsNotEnough() {
    let signals = ForYouSignals(
      participated: ["swiftui", "swiftui", "oneoff"],
      opened: ["astronomy", "astronomy", "glanced"],
    )
    let ranked = ForYouRanking.ranked(from: signals)
    #expect(ranked.qualified.map(\.name) == ["swiftui", "astronomy"])
    #expect(ranked.qualified.first?.reason == .participated)
    #expect(ranked.qualified.first?.score == 3)
    #expect(ranked.qualified.last?.reason == .opened)
    #expect(ranked.qualified.last?.breakdown.opened == 2)
    #expect(Set(ranked.unqualified.map(\.name)) == ["oneoff", "glanced"])
  }

  @Test func capsEachKindOfSignal() {
    let binge = ForYouSignals(upvoted: Array(repeating: "binge", count: 40), saved: ["a", "a", "b", "b"])
    let candidates = ForYouRanking.candidates(from: binge)
    #expect(candidates.first { $0.name == "binge" }?.score == 5)
  }

  @Test func relevanceThresholdIsHomesMedian() {
    #expect(ForYouRanking.relevanceThreshold(homeScores: []) == nil)
    #expect(ForYouRanking.relevanceThreshold(homeScores: [0.9, 0.1, 0.5]) == 0.5)
    #expect(ForYouRanking.relevanceThreshold(homeScores: [0.2, 0.4, 0.6, 0.8]) == 0.5)
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

  private static func post(_ id: String, sub: String, title: String = "A post", over18: Bool = false, crosspostOf original: PostData? = nil) -> PostData {
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
    if let original, let parent = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) {
      json["crosspost_parent_list"] = [parent]
    }
    guard let data = try? JSONSerialization.data(withJSONObject: json), let post = try? JSONDecoder().decode(PostData.self, from: data)
    else { fatalError("The sample post doesn't decode") }
    return post
  }

  private final class Calls: Sendable {
    let home = Mutex<[String?]>([])
    let suggestions = Mutex<[([String], String?)]>([])
    let upvoted = Mutex(0)
    let followed = Mutex<[String]>(["homelab"])
    let excluded = Mutex<Set<String>>([])
    /// Replaces the upvoted posts when set.
    let upvotedPosts = Mutex<[PostData]?>(nil)
    /// Runs while a profile builds, after its upvotes are asked for.
    let duringBuild = Mutex<(@Sendable () async -> Void)?>(nil)
    let scorersMade = Mutex(0)
    let participation = Mutex<[RedditAPI.ActivityItem]?>([])
    let opened = Mutex<[ForYouOpenedPost]>([])
  }

  private func engine(
    calls: Calls,
    homeFails: Bool = false,
    suggestionsFail: Bool = false,
    homeAfter: String? = "t3_h8",
    homeCount: Int = 8,
    homeCrosspostFrom: String? = nil,
    suggestionPage: (@Sendable (_ after: String?) -> ([PostData], String?)?)? = nil,
    scorer: (@Sendable (_ title: String) -> Double?)? = nil,
    scorerForBuild: (@Sendable (_ build: Int, _ title: String) -> Double?)? = nil,
  ) -> ForYouEngine {
    let sources = ForYouSources(
      home: { _, after, _, _ in
        calls.home.withLock { $0.append(after) }
        guard !homeFails else { return nil }
        var posts = (0 ..< homeCount).map { Self.post("h\($0)\(after ?? "")", sub: "homelab") }
        if let homeCrosspostFrom {
          posts.append(Self.post("xp\(after ?? "")", sub: "homelab", crosspostOf: Self.post("orig", sub: homeCrosspostFrom)))
        }
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
        if let duringBuild = calls.duringBuild.withLock({ $0 }) {
          await duringBuild()
        }
        if let posts = calls.upvotedPosts.withLock({ $0 }) {
          return posts
        }
        return [
          Self.post("u1", sub: "selfhosted", title: "Proxmox cluster tips"), Self.post("u2", sub: "espresso", title: "Espresso puck prep"),
          Self.post("u3", sub: "selfhosted", title: "Backups for a home lab"), Self.post("u4", sub: "espresso", title: "Light roast tips"),
          Self.post("u5", sub: "canada", title: "A one-off upvote"),
        ]
      },
      saved: { _, _ in [] },
      participation: { _, _ in calls.participation.withLock { $0 } },
      opened: { _ in calls.opened.withLock { $0 } },
      related: { _, _ in [] },
      subscribed: { _ in calls.followed.withLock { $0 } },
      excluded: { calls.excluded.withLock { $0 } },
    )
    return ForYouEngine(sources: sources, makeScorer: { _ in
      let build = calls.scorersMade.withLock { count in
        count += 1
        return count
      }
      if let scorerForBuild {
        return StubScorer { scorerForBuild(build, $0) }
      }
      return scorer.map(StubScorer.init)
    })
  }

  private final class StubScorer: TitleScoring {
    let scoring: @Sendable (String) -> Double?
    init(_ scoring: @escaping @Sendable (String) -> Double?) {
      self.scoring = scoring
    }

    func score(_ title: String) -> Double? {
      scoring(title)
    }

    var likedCount: Int {
      1
    }
  }

  @Test func suggestionsLessRelevantThanATypicalHomePostAreLeftOut() async throws {
    let calls = Calls()
    let engine = engine(calls: calls, scorer: { $0.contains("server") ? 0.9 : $0 == "A post" ? 0.5 : 0.1 })
    let page = try #require(await engine.page(after: nil, sort: .best, limit: 8, credential: Self.credential))
    #expect(Set(page.reasons.keys) == ["t3_s1"])

    let diagnostics = try #require(await engine.diagnostics(account: ForYouEngine.Account(Self.credential)))
    #expect(diagnostics.lastPage?.threshold == 0.5)
    #expect(diagnostics.lastPage?.eligible == 2)
    #expect(diagnostics.lastPage?.relevant == 1)
    #expect(diagnostics.lastPage?.shown == 1)
    #expect(diagnostics.unqualified.map(\.name) == ["canada"])
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

  @Test func anEmptyHomeWithFailedSuggestionsFailsThePage() async {
    let calls = Calls()
    let page = await engine(calls: calls, suggestionsFail: true, homeAfter: nil, homeCount: 0)
      .page(after: nil, sort: .best, limit: 8, credential: Self.credential)
    #expect(page == nil)
  }

  @Test func followingASuggestedSubredditStopsItsSuggestions() async throws {
    let calls = Calls()
    let engine = engine(calls: calls)
    let first = try #require(await engine.page(after: nil, sort: .best, limit: 8, credential: Self.credential))
    #expect(first.posts.contains { $0.subreddit == "espresso" })
    calls.followed.withLock { $0.append("espresso") }
    let again = try #require(await engine.page(after: nil, sort: .best, limit: 8, credential: Self.credential))
    #expect(!again.posts.contains { $0.subreddit == "espresso" })
  }

  @Test func signingInAgainOnACredentialStartsOver() async {
    let calls = Calls()
    let engine = engine(calls: calls)
    _ = await engine.page(after: nil, sort: .best, limit: 8, credential: Self.credential)
    var reauthorized = Self.credential
    reauthorized.refreshToken = "placeholder-other-grant"
    _ = await engine.page(after: nil, sort: .best, limit: 8, credential: reauthorized)
    #expect(calls.upvoted.withLock { $0 } == 2)
    #expect(await engine.diagnostics(account: ForYouEngine.Account(Self.credential)) != nil)
  }

  @Test func crosspostsOfNSFWPostsAreNotSuggested() async throws {
    let calls = Calls()
    let engine = engine(calls: calls, homeAfter: nil) { _ in
      ([Self.post("xnsfw", sub: "selfhosted", crosspostOf: Self.post("orig", sub: "elsewhere", over18: true)), Self.post("ok", sub: "espresso")], nil)
    }
    let page = try #require(await engine.page(after: nil, sort: .best, limit: 8, credential: Self.credential))
    #expect(Set(page.reasons.keys) == ["t3_ok"])
  }

  @Test func workingSuggestionsOutAgainKeepsAPagingFeedGoing() async throws {
    let calls = Calls()
    let engine = engine(calls: calls, homeAfter: nil)
    let first = try #require(await engine.page(after: nil, sort: .best, limit: 8, credential: Self.credential))
    await engine.invalidate()
    #expect(await engine.diagnostics(account: ForYouEngine.Account(Self.credential)) == nil)

    let next = try #require(await engine.page(after: first.after, sort: .best, limit: 8, credential: Self.credential))
    #expect(next.reasons.count == 2)
    #expect(calls.upvoted.withLock { $0 } == 1)

    _ = await engine.page(after: nil, sort: .best, limit: 8, credential: Self.credential)
    #expect(calls.upvoted.withLock { $0 } == 2)
  }

  @Test func aCrosspostSeenAgainOnRefreshCountsOnce() async throws {
    let calls = Calls()
    let engine = engine(calls: calls, homeCrosspostFrom: "DataHoarder")
    _ = await engine.page(after: nil, sort: .best, limit: 8, credential: Self.credential)
    _ = await engine.page(after: nil, sort: .best, limit: 8, credential: Self.credential)
    await engine.invalidate()
    _ = await engine.page(after: nil, sort: .best, limit: 8, credential: Self.credential)
    let diagnostics = try #require(await engine.diagnostics(account: ForYouEngine.Account(Self.credential)))
    #expect(diagnostics.unqualified.first { $0.name == "DataHoarder" }?.breakdown.crossposted.count == 1)
    #expect(!diagnostics.candidates.contains { $0.name == "DataHoarder" })
  }

  @Test func crosspostsFromExcludedSubredditsAreNotSuggested() async throws {
    let calls = Calls()
    calls.excluded.withLock { $0 = ["blocked"] }
    let engine = engine(calls: calls, homeAfter: nil) { _ in
      ([Self.post("xblocked", sub: "selfhosted", crosspostOf: Self.post("orig", sub: "Blocked")), Self.post("ok", sub: "espresso")], nil)
    }
    let page = try #require(await engine.page(after: nil, sort: .best, limit: 8, credential: Self.credential))
    #expect(Set(page.reasons.keys) == ["t3_ok"])
  }

  @Test func aChainKeepsItsSuggestionsWhenTheyAreWorkedOutAgainElsewhere() async throws {
    let calls = Calls()
    let engine = engine(calls: calls, homeAfter: nil)
    let first = try #require(await engine.page(after: nil, sort: .best, limit: 8, credential: Self.credential))

    // Another window works the suggestions out again, and they no longer include these.
    calls.upvotedPosts.withLock { $0 = [Self.post("a1", sub: "astronomy"), Self.post("a2", sub: "astronomy")] }
    await engine.invalidate()
    _ = await engine.page(after: nil, sort: .best, limit: 8, credential: Self.credential)
    let rebuilt = try #require(await engine.diagnostics(account: ForYouEngine.Account(Self.credential)))
    #expect(rebuilt.candidates.map(\.name) == ["astronomy"])

    let next = try #require(await engine.page(after: first.after, sort: .best, limit: 8, credential: Self.credential))
    #expect(Set(next.reasons.values) == [.upvoted])
    #expect(next.reasons.count == 2)
  }

  @Test func workingSuggestionsOutAgainDuringABuildIsNotUndone() async {
    let calls = Calls()
    let engine = engine(calls: calls)
    calls.duringBuild.withLock { $0 = { await engine.invalidate() } }
    _ = await engine.page(after: nil, sort: .best, limit: 8, credential: Self.credential)
    calls.duringBuild.withLock { $0 = nil }
    #expect(await engine.diagnostics(account: ForYouEngine.Account(Self.credential)) == nil)
    _ = await engine.page(after: nil, sort: .best, limit: 8, credential: Self.credential)
    #expect(calls.upvoted.withLock { $0 } == 2)
  }

  @Test func aChainDoesNotJudgeItsSuggestionsByAnotherWindowsThreshold() async throws {
    let calls = Calls()
    // The second build scores Home's titles much higher, so its threshold would cut everything.
    let engine = engine(calls: calls, homeAfter: nil, scorerForBuild: { build, title in
      title == "A post" ? (build == 1 ? 0.5 : 0.95) : title.contains("server") ? 0.9 : 0.1
    })
    let first = try #require(await engine.page(after: nil, sort: .best, limit: 8, credential: Self.credential))
    #expect(Set(first.reasons.keys) == ["t3_s1"])

    await engine.invalidate()
    _ = await engine.page(after: nil, sort: .best, limit: 8, credential: Self.credential)

    let next = try #require(await engine.page(after: first.after, sort: .best, limit: 8, credential: Self.credential))
    #expect(!next.reasons.isEmpty)
  }

  @Test func readPostsAndCommentsSuggestTheirSubreddits() async throws {
    let calls = Calls()
    calls.upvotedPosts.withLock { $0 = [] }
    calls.participation.withLock {
      $0 = [RedditAPI.ActivityItem(subreddit: "SwiftUI", title: "Navigation question"), RedditAPI.ActivityItem(subreddit: "SwiftUI", title: nil)]
    }
    calls.opened.withLock {
      $0 = [
        ForYouOpenedPost(id: "t3_o1", subreddit: "astronomy", title: "Saturn tonight", lastOpened: Date(), seconds: 40),
        ForYouOpenedPost(id: "t3_o2", subreddit: "astronomy", title: "Comet photo", lastOpened: Date(), seconds: 25),
      ]
    }
    let engine = engine(calls: calls)
    _ = await engine.page(after: nil, sort: .best, limit: 8, credential: Self.credential)
    let diagnostics = try #require(await engine.diagnostics(account: ForYouEngine.Account(Self.credential)))
    #expect(Set(diagnostics.candidates.map(\.name)) == ["SwiftUI", "astronomy"])
    #expect(diagnostics.candidates.first { $0.name == "astronomy" }?.reason == .opened)
    #expect(diagnostics.participatedCount == 2)
    #expect(diagnostics.openedCount == 2)
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

@MainActor
@Suite(.serialized)
struct ForYouHistoryTests {
  private func visit(_ id: String, _ subreddit: String, seconds: Double, at date: Date) -> ForYouOpenedPost {
    ForYouOpenedPost(id: id, subreddit: subreddit, title: "Post \(id)", lastOpened: date, seconds: seconds)
  }

  @Test func keepsPostsReadLongEnoughNewestFirstAndAddsUpVisits() {
    let account = UUID()
    defer { ForYouHistory.forget(account: account) }
    let start = Date(timeIntervalSince1970: 1_000_000)
    ForYouHistory.record(visit("t3_a", "astronomy", seconds: 6, at: start), account: account)
    ForYouHistory.record(visit("t3_b", "pics", seconds: 3, at: start.addingTimeInterval(10)), account: account)
    ForYouHistory.record(visit("t3_a", "astronomy", seconds: 6, at: start.addingTimeInterval(20)), account: account)

    let read = ForYouHistory.read(account: account)
    #expect(read.map(\.id) == ["t3_a"])
    #expect(read.first?.seconds == 12)
    #expect(ForYouHistory.read(account: UUID()).isEmpty)

    ForYouHistory.forget(account: account)
    #expect(ForYouHistory.read(account: account).isEmpty)
  }

  @Test func aVisitOpenWhenHistoryIsErasedIsNotWrittenBack() {
    let account = UUID()
    let other = UUID()
    defer {
      ForYouHistory.forget(account: account)
      ForYouHistory.forget(account: other)
    }
    let start = Date(timeIntervalSince1970: 1_000_000)
    ForYouHistory.began("t3_a", account: account, at: start)
    ForYouHistory.began("t3_b", account: other, at: start)
    ForYouHistory.forget(account: account)
    ForYouHistory.ended("t3_a", subreddit: "astronomy", title: "Saturn", at: start.addingTimeInterval(60))
    ForYouHistory.ended("t3_b", subreddit: "pics", title: "Kept", at: start.addingTimeInterval(60))
    #expect(ForYouHistory.read(account: account).isEmpty)
    #expect(ForYouHistory.read(account: other).map(\.id) == ["t3_b"])

    ForYouHistory.began("t3_c", account: other, at: start)
    ForYouHistory.clear()
    ForYouHistory.ended("t3_c", subreddit: "pics", title: "Gone", at: start.addingTimeInterval(60))
    #expect(ForYouHistory.read(account: other).isEmpty)
  }

  @Test func keepsOnlyTheLatestPosts() {
    let account = UUID()
    defer { ForYouHistory.forget(account: account) }
    for index in 0 ..< ForYouHistory.limit + 5 {
      ForYouHistory.record(visit("t3_\(index)", "sub", seconds: 30, at: Date()), account: account)
    }
    let read = ForYouHistory.read(account: account)
    #expect(read.count == ForYouHistory.limit)
    #expect(read.first?.id == "t3_\(ForYouHistory.limit + 4)")
  }
}
