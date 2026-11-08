//
//  ForYouFeed.swift
//  Helio
//

import CoreData
import Defaults
import Foundation
import os

let forYouLogger = Logger(subsystem: "com.sertacozercan.helio", category: "ForYou")

/// The network and local data For You is made from. Tests replace it.
struct ForYouSources: Sendable {
  var home: @Sendable (_ sort: SubListingSortOption, _ after: String?, _ limit: Int, _ credential: RedditCredential) async -> ([PostData], String?)?
  /// A page of the multireddit of `subs`, by hot.
  var suggestions: @Sendable (_ subs: [String], _ after: String?, _ limit: Int, _ credential: RedditCredential) async -> ([PostData], String?)?
  var upvoted: @Sendable (_ userName: String, _ credential: RedditCredential) async -> [PostData]?
  var saved: @Sendable (_ userName: String, _ credential: RedditCredential) async -> [RedditAPI.ActivityItem]?
  /// The account's comments and posts.
  var participation: @Sendable (_ userName: String, _ credential: RedditCredential) async -> [RedditAPI.ActivityItem]? = { _, _ in [] }
  /// The posts read on this device, newest first (`ForYouHistory`).
  var opened: @Sendable (_ credential: RedditCredential) -> [ForYouOpenedPost] = { _ in [] }
  /// The posts the account already saw in For You or opened, by fullname: For You leaves them out.
  var seen: @Sendable (_ credential: RedditCredential) async -> Set<String> = { _ in [] }
  /// Which of these post ids (without their kind) were read in Helio (`SeenPost`): For You leaves
  /// them out too, so the feed doesn't hide them again on its own.
  var read: @Sendable (_ ids: [String]) async -> Set<String> = { _ in [] }
  var related: @Sendable (_ subreddit: String, _ credential: RedditCredential) async -> [ForYouRelatedSub]?
  /// The names of the subreddits the account follows, as last synced.
  var subscribed: @Sendable (_ credential: RedditCredential) async -> [String]
  /// Lowercased names never to suggest.
  var excluded: @Sendable () -> Set<String>

  static let live = ForYouSources(
    home: { sort, after, limit, credential in
      await RedditAPI.shared.fetchSubPosts("", limit: limit, sort: sort, after: after, altCredential: credential).map { (posts(in: $0.0), $0.1) }
    },
    suggestions: { subs, after, limit, credential in
      await RedditAPI.shared.fetchSubPosts("/r/\(subs.joined(separator: "+"))", limit: limit, sort: .hot, after: after, altCredential: credential).map { (posts(in: $0.0), $0.1) }
    },
    upvoted: { userName, credential in
      await RedditAPI.shared.fetchUpvotedPosts(userName, altCredential: credential)
    },
    saved: { userName, credential in
      await RedditAPI.shared.fetchSavedItems(userName, altCredential: credential)
    },
    participation: { userName, credential in
      await RedditAPI.shared.fetchParticipation(userName, altCredential: credential)
    },
    opened: { credential in
      ForYouHistory.read(ForYouHistory.Owner(credential))
    },
    seen: { credential in
      await MainActor.run { ForYouHistory.seen(ForYouHistory.Owner(credential)) }
    },
    read: { ids in
      guard !ids.isEmpty else { return [] }
      let context = PersistenceController.shared.container.newBackgroundContext()
      return await context.perform {
        let request = NSFetchRequest<SeenPost>(entityName: "SeenPost")
        request.predicate = NSPredicate(format: "postID IN %@", ids)
        return Set(((try? context.fetch(request)) ?? []).compactMap(\.postID))
      }
    },
    related: { subreddit, credential in
      await RedditAPI.shared.fetchRelatedSubs(subreddit, altCredential: credential)
    },
    subscribed: { credential in
      let context = PersistenceController.shared.container.newBackgroundContext()
      return await context.perform {
        let request = CachedSub.fetchRequest()
        request.predicate = NSPredicate(format: "helioCredentialID == %@ AND user_is_subscriber == YES", credential.id as CVarArg)
        return ((try? context.fetch(request)) ?? []).compactMap(\.display_name)
      }
    },
    excluded: {
      Set((Defaults[.forYouDismissedSubs] + Defaults[.filteredSubreddits]).map { $0.lowercased() })
    },
  )

  private static func posts(in children: [ListingChild<Either<PostData, CommentData>>]?) -> [PostData] {
    (children ?? []).compactMap { child in
      if case let .first(post) = child.data {
        post
      } else {
        nil
      }
    }
  }
}

/// How a page's suggestions were narrowed down, for the settings' explanation.
struct ForYouPageStats: Sendable {
  /// The relevance a suggestion had to reach; nil without the embedding.
  var threshold: Double?
  /// Posts from the suggested subreddits.
  var fetched = 0
  /// Left after followed, excluded, NSFW and pinned posts.
  var eligible = 0
  /// Left after the relevance threshold.
  var relevant = 0
  var shown = 0
}

/// What For You worked out for an account and why, shown in Settings.
struct ForYouDiagnostics: Sendable {
  let builtAt: Date
  let seeds: [String]
  let relatedFailures: Int
  /// nil when they failed to load.
  let upvotedCount: Int?
  let savedCount: Int?
  let participatedCount: Int?
  /// Posts read for a while on this device.
  let openedCount: Int
  /// nil without the embedding.
  let likedTitles: Int?
  var candidates: [ForYouCandidate]
  let unqualified: [ForYouCandidate]
  let lastPage: ForYouPageStats?
}

/// A page of For You: Home's page with suggested posts mixed in, and why each was suggested.
struct ForYouPage {
  var posts: [PostData]
  /// By post fullname.
  var reasons: [String: ForYouReason]
  var after: String?
}

/// Builds For You: the account's Home, with posts mixed in from subreddits it doesn't follow but
/// seems to like. Reddit's own recommendations aren't in its public API, so the suggestions are
/// worked out here, from what the account upvotes and saves, what its subreddits list as
/// related and what gets crossposted into them, and ranked with an on-device text embedding.
/// What it works out stays in memory.
actor ForYouEngine {
  static let shared = ForYouEngine()

  /// What For You keeps its state by: an account's sign-in, not just its credential, as signing
  /// in again on a credential can put another account behind the same id.
  struct Account: Hashable, Sendable {
    let credentialID: UUID
    let authorization: RedditCredential.AuthorizationID?

    init(_ credential: RedditCredential) {
      credentialID = credential.id
      authorization = credential.authorizationID
    }
  }

  struct Profile {
    let builtAt: Date
    /// Which build this is: page chains compare it to know whether a threshold still applies.
    let generation: Int
    var candidates: [ForYouCandidate]
    /// Subreddits the signals point at too weakly to suggest, for the settings' explanation.
    let unqualified: [ForYouCandidate]
    let subscribed: Set<String>
    let scorer: (any TitleScoring)?
    let seeds: [String]
    let relatedFailures: Int
    /// nil when they failed to load.
    let upvotedCount: Int?
    let savedCount: Int?
    let participatedCount: Int?
    let openedCount: Int
    /// Asked to be worked out again: the next first page rebuilds it, while a feed already
    /// paging keeps using it.
    var stale = false

    /// Whether the account's upvotes or saves loaded; without them it's rebuilt sooner.
    var complete: Bool {
      upvotedCount != nil || savedCount != nil || participatedCount != nil
    }
  }

  static let freshFor: TimeInterval = 6 * 60 * 60
  static let incompleteFreshFor: TimeInterval = 15 * 60
  /// One suggestion after this many Home posts.
  static let suggestEvery = 4
  static let suggestionsPageSize = 25
  static let maxCrossposts = 200
  static let maxCandidates = 15
  /// Suggestion pages in a row with nothing to show, once Home ran out, before giving up.
  static let maxEmptySuggestionPages = 5
  /// Home pages in a row of only posts already seen to skip, before showing none of them.
  static let maxSeenHomePages = 5

  private let sources: ForYouSources
  private let now: @Sendable () -> Date
  private var profiles: [Account: Profile] = [:]
  private var building: [Account: Task<Profile, Never>] = [:]
  private struct NotedCrosspost {
    /// The fullname of the post in Home.
    let homePost: String
    let crosspost: ForYouSignals.Crosspost
  }

  private var crossposts: [Account: [NotedCrosspost]] = [:]
  private var lastPageStats: [Account: ForYouPageStats] = [:]
  /// Numbers each built profile, so a page chain knows whether its relevance threshold came from
  /// the scorer it's using now.
  private var builtProfiles = 0
  /// Counts requests to work the suggestions out again, so a build started before one doesn't
  /// pass for fresh.
  private var invalidations = 0
  /// Lowercased names dismissed since launch, left out even by chains that started before.
  private var dismissed: Set<String> = []

  private let makeScorer: @Sendable (_ likedTitles: [String]) -> (any TitleScoring)?

  init(sources: ForYouSources = .live, now: @escaping @Sendable () -> Date = { Date() },
       makeScorer: @escaping @Sendable (_ likedTitles: [String]) -> (any TitleScoring)? = { InterestScorer(likedTitles: $0) })
  {
    self.sources = sources
    self.now = now
    self.makeScorer = makeScorer
  }

  /// The first page without `after`. nil when Home fails to load, when the suggestions do once
  /// Home ran out, or when `after` isn't a For You cursor; otherwise the suggestions failing
  /// leaves just Home.
  func page(after: String?, sort: SubListingSortOption, limit: Int, credential: RedditCredential) async -> ForYouPage? {
    var home: ([PostData], String?)?
    var suggested: ([PostData], String?)?
    let subs: [String]
    let profile: Profile?
    // Why each of `subs` is suggested, by lowercased name. A chain keeps the reasons it started
    // with, so a rebuild elsewhere doesn't drop its suggestions.
    let reasonBySub: [String: ForYouReason]
    // Whether this page asked for suggestions, as opposed to having none left to ask for.
    let wantsSuggestions: Bool
    let account = Account(credential)
    let cursor: ForYouCursor?
    if let after {
      guard let decoded = ForYouCursor(encoded: after) else { return nil }
      cursor = decoded
    } else {
      cursor = nil
    }
    // Like Reddit's, For You doesn't show a post again once the account saw it.
    let seen = await sources.seen(credential)

    if let cursor {
      subs = cursor.subs
      reasonBySub = cursor.reasons
      wantsSuggestions = cursor.suggested != nil && !subs.isEmpty
      async let homePage: ([PostData], String?)? = if cursor.home != nil {
        await fetchHome(sort: sort, after: cursor.home, limit: limit, credential: credential, seen: seen)
      } else {
        nil
      }
      async let suggestedPage = fetchSuggestions(subs: wantsSuggestions ? subs : [], after: cursor.suggested, credential: credential)
      if cursor.home != nil {
        guard let page = await homePage else { return nil }
        home = page
      }
      suggested = await suggestedPage
      profile = profiles[account]
    } else if let fresh = freshProfile(account) {
      subs = fresh.candidates.map(\.name)
      reasonBySub = Self.reasonBySub(fresh)
      wantsSuggestions = !subs.isEmpty
      async let homePage = fetchHome(sort: sort, after: nil, limit: limit, credential: credential, seen: seen)
      async let suggestedPage = fetchSuggestions(subs: subs, after: nil, credential: credential)
      guard let page = await homePage else { return nil }
      home = page
      suggested = await suggestedPage
      profile = fresh
    } else {
      // The first visit: the profile is built from what Home shows, so it waits for Home.
      guard let page = await fetchHome(sort: sort, after: nil, limit: limit, credential: credential, seen: seen) else { return nil }
      home = page
      let built = await buildProfileIfNeeded(credential: credential, home: page.0)
      subs = built.candidates.map(\.name)
      reasonBySub = Self.reasonBySub(built)
      wantsSuggestions = !subs.isEmpty
      suggested = await fetchSuggestions(subs: subs, after: nil, credential: credential)
      profile = built
    }

    let homePosts = home?.0 ?? []
    // Without Home posts, the suggestions are the page, so their failing fails it and its
    // retry can resume, rather than reading as an empty feed or its end.
    if homePosts.isEmpty, wantsSuggestions, suggested == nil {
      return nil
    }
    // Read for each page, so a suggested subreddit stops being suggested once it's followed.
    let followed = await followedSubreddits(credential: credential, profile: profile)
    let threshold = relevanceThreshold(home: homePosts, profile: profile, cursor: cursor)
    let filter = SuggestionFilter(reasons: reasonBySub, followed: followed, excluded: sources.excluded().union(dismissed),
                                  seen: seen, scorer: profile?.scorer, threshold: threshold)
    var suggestedAfter = suggested?.1
    var stats = ForYouPageStats(threshold: threshold)
    var picked = await pickSuggestions(from: unread(suggested?.0 ?? []), home: homePosts, filter: filter, stats: &stats)
    // With Home run out, the suggestions are the feed, and a page whose suggestions were all
    // filtered out would read as its end: look further, as the feed does past read posts. The
    // search is bounded: after this many pages with nothing relevant, the feed ends.
    var emptyPages = 0
    while homePosts.isEmpty, picked.isEmpty, let after = suggestedAfter, emptyPages < Self.maxEmptySuggestionPages {
      guard let next = await fetchSuggestions(subs: subs, after: after, credential: credential) else { return nil }
      suggestedAfter = next.1
      picked = await pickSuggestions(from: unread(next.0), home: [], filter: filter, stats: &stats)
      emptyPages += 1
    }
    lastPageStats[account] = stats

    var reasons: [String: ForYouReason] = [:]
    for post in picked {
      reasons[post.name] = reasonBySub[post.subreddit.lowercased()]
    }
    let next = ForYouCursor(home: home?.1, suggested: suggestedAfter, subs: subs, reasons: reasonBySub,
                            threshold: threshold, generation: profile?.generation)
    return ForYouPage(posts: ForYouRanking.interleave(homePosts, picked, every: Self.suggestEvery), reasons: reasons, after: next.encoded)
  }

  /// The subreddits the account follows now, by lowercased name; the ones it followed when the
  /// profile was built until the subscriptions first sync.
  private func followedSubreddits(credential: RedditCredential, profile: Profile?) async -> Set<String> {
    let current = await Set(sources.subscribed(credential).map { $0.lowercased() })
    return current.isEmpty ? profile?.subscribed ?? [] : current
  }

  private static func reasonBySub(_ profile: Profile) -> [String: ForYouReason] {
    Dictionary(profile.candidates.map { ($0.name.lowercased(), $0.reason) }, uniquingKeysWith: { first, _ in first })
  }

  /// How close to the account's interests a suggestion has to be: as close as a typical post of
  /// this page's Home, or, once Home ran out, of the last Home page in this chain. That one
  /// holds only while the chain scores with the same profile; after the suggestions were worked
  /// out again, its scale may not match, so suggestions go unchecked rather than wrongly cut.
  /// nil without the embedding.
  private func relevanceThreshold(home: [PostData], profile: Profile?, cursor: ForYouCursor?) -> Double? {
    guard let profile, let scorer = profile.scorer else { return nil }
    if let threshold = ForYouRanking.relevanceThreshold(homeScores: home.compactMap { scorer.score($0.title) }) {
      return threshold
    }
    return cursor?.generation == profile.generation ? cursor?.threshold : nil
  }

  /// What a page's suggestions are checked against.
  private struct SuggestionFilter {
    /// Why each suggested subreddit is suggested, by lowercased name: posts from others are left out.
    let reasons: [String: ForYouReason]
    /// Lowercased names of the subreddits the account follows.
    let followed: Set<String>
    /// Lowercased names of filtered and dismissed subreddits.
    let excluded: Set<String>
    /// Fullnames of the posts the account already saw.
    let seen: Set<String>
    let scorer: (any TitleScoring)?
    /// The relevance a suggestion has to reach; nil without the embedding.
    let threshold: Double?
  }

  /// The suggestions to show beside `home`: one per few Home posts, or all of them once Home
  /// ran out. Leaves out followed, excluded, NSFW and pinned posts, and, with the embedding,
  /// posts less relevant than the threshold.
  /// `posts` without the ones read in Helio. For You filters read posts itself rather than
  /// leaving it to the feed, so one bound covers all the pages it skips.
  private func unread(_ posts: [PostData]) async -> [PostData] {
    let read = await sources.read(posts.map(\.id))
    return read.isEmpty ? posts : posts.filter { !read.contains($0.id) }
  }

  private func pickSuggestions(from posts: [PostData], home: [PostData], filter: SuggestionFilter, stats: inout ForYouPageStats) -> [PostData] {
    let homeIDs = Set(home.map(\.name))
    let eligible = posts.filter { post in
      let sub = post.subreddit.lowercased()
      // A crosspost shows its original, which may be NSFW, or from an excluded subreddit, when
      // the crosspost itself isn't.
      let original = post.crosspost_parent_list?.first
      let over18 = (post.over_18 ?? false) || (original?.over_18 ?? false)
      let excluded = filter.excluded.contains(sub) || original.map { filter.excluded.contains($0.subreddit.lowercased()) } ?? false
      return !over18 && !excluded && !(post.stickied ?? false) && !homeIDs.contains(post.name) && !filter.seen.contains(post.name)
        && !filter.followed.contains(sub) && filter.reasons[sub] != nil
    }
    let scores = Dictionary(eligible.compactMap { post in filter.scorer?.score(post.title).map { (post.name, $0) } }, uniquingKeysWith: { first, _ in first })
    let relevant = filter.threshold.map { threshold in eligible.filter { scores[$0.name].map { $0 >= threshold } ?? false } } ?? eligible
    let picked = ForYouRanking.pick(relevant, count: home.isEmpty ? relevant.count : home.count / Self.suggestEvery,
                                    perSub: home.isEmpty ? .max : 2, sub: \.subreddit, score: { scores[$0.name] })
    stats.fetched += posts.count
    stats.eligible += eligible.count
    stats.relevant += relevant.count
    stats.shown += picked.count
    return picked
  }

  /// What For You worked out for `account`, for the settings' explanation. nil before it's
  /// been opened.
  func diagnostics(account: Account) -> ForYouDiagnostics? {
    guard let profile = profiles[account], !profile.stale else { return nil }
    return ForYouDiagnostics(
      builtAt: profile.builtAt,
      seeds: profile.seeds,
      relatedFailures: profile.relatedFailures,
      upvotedCount: profile.upvotedCount,
      savedCount: profile.savedCount,
      participatedCount: profile.participatedCount,
      openedCount: profile.openedCount,
      likedTitles: profile.scorer?.likedCount,
      candidates: profile.candidates,
      unqualified: profile.unqualified,
      lastPage: lastPageStats[account],
    )
  }

  /// Works the suggestions out again the next time For You loads from the top. A feed already
  /// showing keeps paging with the suggestions it started with.
  func invalidate() {
    invalidations += 1
    for account in profiles.keys {
      profiles[account]?.stale = true
    }
  }

  /// Stops suggesting `subreddit`, from the next page on.
  func dismiss(_ subreddit: String) {
    let key = subreddit.lowercased()
    dismissed.insert(key)
    for (id, var profile) in profiles {
      profile.candidates.removeAll { $0.name.lowercased() == key }
      profiles[id] = profile
    }
  }

  /// Lets `subreddit` be suggested again, once the suggestions are worked out again.
  func undismiss(_ subreddit: String) {
    dismissed.remove(subreddit.lowercased())
    invalidate()
  }

  private func freshProfile(_ account: Account) -> Profile? {
    guard let profile = profiles[account], !profile.stale else { return nil }
    let lifetime = profile.complete ? Self.freshFor : Self.incompleteFreshFor
    return now().timeIntervalSince(profile.builtAt) < lifetime ? profile : nil
  }

  /// Home's next page without the posts already seen: when a whole page was, the one after it,
  /// up to a few, so a feed of seen posts doesn't read as the end of Home. After that, the last
  /// page as it is: seen posts again rather than an empty page, which would end the feed.
  private func fetchHome(sort: SubListingSortOption, after: String?, limit: Int, credential: RedditCredential, seen: Set<String>) async -> ([PostData], String?)? {
    var after = after
    var skipped = 0
    while true {
      guard let page = await sources.home(sort, after, limit, credential) else { return nil }
      noteCrossposts(in: page.0, account: Account(credential))
      let unseen = await unread(page.0.filter { !seen.contains($0.name) })
      if !unseen.isEmpty || page.1 == nil {
        return (unseen, page.1)
      }
      if skipped == Self.maxSeenHomePages {
        return page
      }
      skipped += 1
      after = page.1
    }
  }

  private func fetchSuggestions(subs: [String], after: String?, credential: RedditCredential) async -> ([PostData], String?)? {
    guard !subs.isEmpty else { return nil }
    return await sources.suggestions(subs, after, Self.suggestionsPageSize, credential)
  }

  /// Crossposts in Home, for the next time the profile is built. Each Home post counts once,
  /// however often a refresh shows it again.
  private func noteCrossposts(in posts: [PostData], account: Account) {
    var noted = crossposts[account, default: []]
    var seen = Set(noted.map(\.homePost))
    for post in posts {
      guard let original = post.crosspost_parent_list?.first, seen.insert(post.name).inserted else { continue }
      noted.append(NotedCrosspost(homePost: post.name, crosspost: ForYouSignals.Crosspost(from: original.subreddit, into: post.subreddit)))
    }
    crossposts[account] = Array(noted.suffix(Self.maxCrossposts))
  }

  /// One build at a time per account, shared by the pages that need it.
  private func buildProfileIfNeeded(credential: RedditCredential, home: [PostData]) async -> Profile {
    if let fresh = freshProfile(Account(credential)) {
      return fresh
    }
    if let task = building[Account(credential)] {
      return await task.value
    }
    let invalidationsBefore = invalidations
    let task = Task { await self.buildProfile(credential: credential, home: home) }
    building[Account(credential)] = task
    var profile = await task.value
    building[Account(credential)] = nil
    // Asked to be worked out again while this built from older signals: this page uses it, and
    // the next first page builds another.
    profile.stale = invalidations != invalidationsBefore
    profiles[Account(credential)] = profile
    return profile
  }

  private func buildProfile(credential: RedditCredential, home: [PostData]) async -> Profile {
    let sources = sources
    let userName = credential.userName.flatMap { $0.isEmpty ? nil : $0 }
    async let upvotedFetch: [PostData]? = if let userName {
      await sources.upvoted(userName, credential)
    } else {
      nil
    }
    async let savedFetch: [RedditAPI.ActivityItem]? = if let userName {
      await sources.saved(userName, credential)
    } else {
      nil
    }
    async let participationFetch: [RedditAPI.ActivityItem]? = if let userName {
      await sources.participation(userName, credential)
    } else {
      nil
    }
    var subscribed = await Set(sources.subscribed(credential).map { $0.lowercased() })
    // Before the subscriptions first sync, Home's subreddits are the ones followed.
    if subscribed.isEmpty {
      subscribed = Set(home.map { $0.subreddit.lowercased() })
    }
    let opened = sources.opened(credential)
    let upvoted = await upvotedFetch
    let saved = await savedFetch
    let participated = await participationFetch

    // The followed subreddits the account is most active in, by what it does there.
    let engagement = (upvoted?.map(\.subreddit) ?? []) + (participated?.map(\.subreddit) ?? []) + opened.map(\.subreddit)
    let seeds = ForYouRanking.seeds(upvoted: engagement, home: home.map(\.subreddit), subscribed: subscribed)
    let lookups = await withTaskGroup(of: (Int, [ForYouSignals.Related]?).self) { group in
      for (index, seed) in seeds.enumerated() {
        group.addTask {
          await (index, sources.related(seed, credential)?.map { ForYouSignals.Related(seed: seed, sub: $0) })
        }
      }
      var results: [(Int, [ForYouSignals.Related]?)] = []
      for await result in group {
        results.append(result)
      }
      return results.sorted { $0.0 < $1.0 }.map(\.1)
    }
    let related = lookups.flatMap { $0 ?? [] }

    let signals = ForYouSignals(
      subscribed: subscribed,
      excluded: sources.excluded(),
      upvoted: upvoted?.map(\.subreddit) ?? [],
      saved: saved?.map(\.subreddit) ?? [],
      participated: participated?.map(\.subreddit) ?? [],
      opened: opened.map(\.subreddit),
      related: related,
      crossposts: crossposts[Account(credential)]?.map(\.crosspost) ?? [],
    )
    // The latest of each kind, so no one kind crowds out the others.
    let likedTitles = Array((upvoted?.map(\.title) ?? []).prefix(75)) + Array((saved?.compactMap(\.title) ?? []).prefix(50))
      + Array((participated?.compactMap(\.title) ?? []).prefix(50)) + Array(opened.map(\.title).prefix(75))
    let ranked = ForYouRanking.ranked(from: signals)
    let candidates = Array(ranked.qualified.prefix(Self.maxCandidates))
    let relatedFailures = lookups.count { $0 == nil }
    forYouLogger.info("Built For You from \(seeds.count) seeds (\(relatedFailures) related lookups failed): \(candidates.count) subreddits to suggest")
    builtProfiles += 1
    return Profile(builtAt: now(), generation: builtProfiles, candidates: candidates, unqualified: Array(ranked.unqualified.prefix(20)), subscribed: subscribed,
                   scorer: makeScorer(likedTitles), seeds: seeds, relatedFailures: relatedFailures,
                   upvotedCount: upvoted?.count, savedCount: saved?.count, participatedCount: participated?.count, openedCount: opened.count)
  }
}

enum ForYouFeed {
  static let id = "foryou"

  static func fetchPosts(_ feed: Subreddit, sort: SubListingSortOption, after: String?, contentWidth: CGFloat, context: FeedItemsManager<SubListingSortOption>.FetchContext) async -> ([RedditEntityType]?, String?)? {
    // From now on, the posts opened are kept for For You (`ForYouHistory`).
    if !Defaults[.forYouUsed] {
      Defaults[.forYouUsed] = true
    }
    guard let page = await ForYouEngine.shared.page(after: after, sort: sort, limit: context.limit, credential: context.credential) else { return nil }
    let posts = Post.initMultiple(datas: page.posts, sub: feed, contentWidth: contentWidth)
    for post in posts {
      if let name = post.data?.name, let reason = page.reasons[name] {
        post.helioData?.forYouReason = reason
      }
    }
    return (posts.map { .post($0) }, page.after)
  }

  /// Notes a row For You showed, so it isn't shown again (`ForYouHistory`).
  @MainActor
  static func shown(_ entity: RedditEntityType) {
    guard case let .post(post) = entity, let credential = RedditCredentialsManager.shared.selectedCredential else { return }
    ForYouHistory.shown(post.fullname, owner: ForYouHistory.Owner(credential))
  }

  /// Stops suggesting `subreddit` in For You.
  @MainActor
  static func dismiss(_ subreddit: String) {
    if !Defaults[.forYouDismissedSubs].contains(where: { $0.caseInsensitiveCompare(subreddit) == .orderedSame }) {
      Defaults[.forYouDismissedSubs].append(subreddit)
    }
    Task { await ForYouEngine.shared.dismiss(subreddit) }
  }

  /// Lets For You suggest `subreddit` again, once it works its suggestions out again.
  @MainActor
  static func undismiss(_ subreddit: String) {
    Defaults[.forYouDismissedSubs].removeAll { $0.caseInsensitiveCompare(subreddit) == .orderedSame }
    Task { await ForYouEngine.shared.undismiss(subreddit) }
  }
}
