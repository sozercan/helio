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
  var saved: @Sendable (_ userName: String, _ credential: RedditCredential) async -> [RedditAPI.SavedItem]?
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

  struct Profile {
    let builtAt: Date
    var candidates: [ForYouCandidate]
    let subscribed: Set<String>
    let scorer: InterestScorer?
    /// Whether the account's upvotes or saves loaded; without them it's rebuilt sooner.
    let complete: Bool
  }

  static let freshFor: TimeInterval = 6 * 60 * 60
  static let incompleteFreshFor: TimeInterval = 15 * 60
  /// One suggestion after this many Home posts.
  static let suggestEvery = 4
  static let suggestionsPageSize = 25
  static let maxCrossposts = 200
  /// Suggestion pages in a row with nothing to show, once Home ran out, before giving up.
  static let maxEmptySuggestionPages = 5

  private let sources: ForYouSources
  private let now: @Sendable () -> Date
  private var profiles: [UUID: Profile] = [:]
  private var building: [UUID: Task<Profile, Never>] = [:]
  private var crossposts: [UUID: [ForYouSignals.Crosspost]] = [:]

  init(sources: ForYouSources = .live, now: @escaping @Sendable () -> Date = { Date() }) {
    self.sources = sources
    self.now = now
  }

  /// The first page without `after`. nil when Home fails to load, when the suggestions do once
  /// Home ran out, or when `after` isn't a For You cursor; otherwise the suggestions failing
  /// leaves just Home.
  func page(after: String?, sort: SubListingSortOption, limit: Int, credential: RedditCredential) async -> ForYouPage? {
    var home: ([PostData], String?)?
    var suggested: ([PostData], String?)?
    let subs: [String]
    let profile: Profile?

    if let after {
      guard let cursor = ForYouCursor(encoded: after) else { return nil }
      subs = cursor.subs
      async let homePage = fetchHome(sort: sort, after: cursor.home, limit: limit, credential: credential, wanted: cursor.home != nil)
      async let suggestedPage = fetchSuggestions(subs: cursor.suggested == nil ? [] : subs, after: cursor.suggested, credential: credential)
      if cursor.home != nil {
        guard let page = await homePage else { return nil }
        home = page
      }
      suggested = await suggestedPage
      // With Home run out, the suggestions failing fails the page, so its retry can resume.
      if cursor.home == nil, suggested == nil {
        return nil
      }
      profile = profiles[credential.id]
    } else if let fresh = freshProfile(credential.id) {
      subs = fresh.candidates.map(\.name)
      async let homePage = fetchHome(sort: sort, after: nil, limit: limit, credential: credential, wanted: true)
      async let suggestedPage = fetchSuggestions(subs: subs, after: nil, credential: credential)
      guard let page = await homePage else { return nil }
      home = page
      suggested = await suggestedPage
      profile = fresh
    } else {
      // The first visit: the profile is built from what Home shows, so it waits for Home.
      guard let page = await fetchHome(sort: sort, after: nil, limit: limit, credential: credential, wanted: true) else { return nil }
      home = page
      let built = await buildProfileIfNeeded(credential: credential, home: page.0)
      subs = built.candidates.map(\.name)
      suggested = await fetchSuggestions(subs: subs, after: nil, credential: credential)
      profile = built
    }

    let homePosts = home?.0 ?? []
    var suggestedAfter = suggested?.1
    var picked = profile.map { pickSuggestions(from: suggested?.0 ?? [], home: homePosts, profile: $0) } ?? []
    // With Home run out, the suggestions are the feed, and a page whose suggestions were all
    // filtered out would read as its end: look further, as the feed does past read posts.
    var emptyPages = 0
    while homePosts.isEmpty, picked.isEmpty, let after = suggestedAfter, let profile, emptyPages < Self.maxEmptySuggestionPages {
      guard let next = await fetchSuggestions(subs: subs, after: after, credential: credential) else { return nil }
      suggestedAfter = next.1
      picked = pickSuggestions(from: next.0, home: [], profile: profile)
      emptyPages += 1
    }

    var reasons: [String: ForYouReason] = [:]
    if let profile {
      let reasonBySub = Self.reasonBySub(profile)
      for post in picked {
        reasons[post.name] = reasonBySub[post.subreddit.lowercased()]
      }
    }
    let cursor = ForYouCursor(home: home?.1, suggested: suggestedAfter, subs: subs)
    return ForYouPage(posts: ForYouRanking.interleave(homePosts, picked, every: Self.suggestEvery), reasons: reasons, after: cursor.encoded)
  }

  private static func reasonBySub(_ profile: Profile) -> [String: ForYouReason] {
    Dictionary(profile.candidates.map { ($0.name.lowercased(), $0.reason) }, uniquingKeysWith: { first, _ in first })
  }

  /// The suggestions to show beside `home`: one per few Home posts, or all of them once Home
  /// ran out, leaving out followed, excluded, NSFW and pinned posts.
  private func pickSuggestions(from posts: [PostData], home: [PostData], profile: Profile) -> [PostData] {
    let reasonBySub = Self.reasonBySub(profile)
    let homeIDs = Set(home.map(\.name))
    let excluded = sources.excluded()
    let eligible = posts.filter { post in
      let sub = post.subreddit.lowercased()
      return !(post.over_18 ?? false) && !(post.stickied ?? false) && !homeIDs.contains(post.name)
        && !excluded.contains(sub) && !profile.subscribed.contains(sub) && reasonBySub[sub] != nil
    }
    let scores = Dictionary(eligible.compactMap { post in profile.scorer?.score(post.title).map { (post.name, $0) } }, uniquingKeysWith: { first, _ in first })
    return ForYouRanking.pick(eligible, count: home.isEmpty ? eligible.count : home.count / Self.suggestEvery,
                              perSub: home.isEmpty ? .max : 2, sub: \.subreddit, score: { scores[$0.name] })
  }

  /// Stops suggesting `subreddit`, from the next page on.
  func dismiss(_ subreddit: String) {
    let key = subreddit.lowercased()
    for (id, var profile) in profiles {
      profile.candidates.removeAll { $0.name.lowercased() == key }
      profiles[id] = profile
    }
  }

  private func freshProfile(_ account: UUID) -> Profile? {
    guard let profile = profiles[account] else { return nil }
    let lifetime = profile.complete ? Self.freshFor : Self.incompleteFreshFor
    return now().timeIntervalSince(profile.builtAt) < lifetime ? profile : nil
  }

  private func fetchHome(sort: SubListingSortOption, after: String?, limit: Int, credential: RedditCredential, wanted: Bool) async -> ([PostData], String?)? {
    guard wanted, let page = await sources.home(sort, after, limit, credential) else { return nil }
    noteCrossposts(in: page.0, account: credential.id)
    return page
  }

  private func fetchSuggestions(subs: [String], after: String?, credential: RedditCredential) async -> ([PostData], String?)? {
    guard !subs.isEmpty else { return nil }
    return await sources.suggestions(subs, after, Self.suggestionsPageSize, credential)
  }

  /// Crossposts in Home, for the next time the profile is built.
  private func noteCrossposts(in posts: [PostData], account: UUID) {
    let found = posts.compactMap { post in
      post.crosspost_parent_list?.first.map { ForYouSignals.Crosspost(from: $0.subreddit, into: post.subreddit) }
    }
    guard !found.isEmpty else { return }
    crossposts[account, default: []].append(contentsOf: found)
    if let count = crossposts[account]?.count, count > Self.maxCrossposts {
      crossposts[account]?.removeFirst(count - Self.maxCrossposts)
    }
  }

  /// One build at a time per account, shared by the pages that need it.
  private func buildProfileIfNeeded(credential: RedditCredential, home: [PostData]) async -> Profile {
    if let fresh = freshProfile(credential.id) {
      return fresh
    }
    if let task = building[credential.id] {
      return await task.value
    }
    let task = Task { await self.buildProfile(credential: credential, home: home) }
    building[credential.id] = task
    let profile = await task.value
    building[credential.id] = nil
    profiles[credential.id] = profile
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
    async let savedFetch: [RedditAPI.SavedItem]? = if let userName {
      await sources.saved(userName, credential)
    } else {
      nil
    }
    var subscribed = await Set(sources.subscribed(credential).map { $0.lowercased() })
    // Before the subscriptions first sync, Home's subreddits are the ones followed.
    if subscribed.isEmpty {
      subscribed = Set(home.map { $0.subreddit.lowercased() })
    }
    let upvoted = await upvotedFetch
    let saved = await savedFetch

    let seeds = ForYouRanking.seeds(upvoted: upvoted?.map(\.subreddit) ?? [], home: home.map(\.subreddit), subscribed: subscribed)
    let related = await withTaskGroup(of: (Int, [ForYouSignals.Related]).self) { group in
      for (index, seed) in seeds.enumerated() {
        group.addTask {
          await (index, (sources.related(seed, credential) ?? []).map { ForYouSignals.Related(seed: seed, sub: $0) })
        }
      }
      var results: [(Int, [ForYouSignals.Related])] = []
      for await result in group {
        results.append(result)
      }
      return results.sorted { $0.0 < $1.0 }.flatMap(\.1)
    }

    let signals = ForYouSignals(
      subscribed: subscribed,
      excluded: sources.excluded(),
      upvoted: upvoted?.map(\.subreddit) ?? [],
      saved: saved?.map(\.subreddit) ?? [],
      related: related,
      crossposts: crossposts[credential.id] ?? [],
    )
    let likedTitles = (upvoted?.map(\.title) ?? []) + (saved?.compactMap(\.title) ?? [])
    let candidates = ForYouRanking.candidates(from: signals)
    forYouLogger.info("Built For You from \(seeds.count) seeds: \(candidates.count) subreddits to suggest")
    return Profile(builtAt: now(), candidates: candidates, subscribed: subscribed,
                   scorer: InterestScorer(likedTitles: Array(likedTitles.prefix(200))),
                   complete: upvoted != nil || saved != nil)
  }
}

enum ForYouFeed {
  static let id = "foryou"

  static func fetchPosts(_ feed: Subreddit, sort: SubListingSortOption, after: String?, contentWidth: CGFloat, context: FeedItemsManager<SubListingSortOption>.FetchContext) async -> ([RedditEntityType]?, String?)? {
    guard let page = await ForYouEngine.shared.page(after: after, sort: sort, limit: context.limit, credential: context.credential) else { return nil }
    let posts = Post.initMultiple(datas: page.posts, sub: feed, contentWidth: contentWidth)
    for post in posts {
      if let name = post.data?.name, let reason = page.reasons[name] {
        post.helioData?.forYouReason = reason
      }
    }
    return (posts.map { .post($0) }, page.after)
  }

  /// Stops suggesting `subreddit` in For You.
  @MainActor
  static func dismiss(_ subreddit: String) {
    if !Defaults[.forYouDismissedSubs].contains(where: { $0.caseInsensitiveCompare(subreddit) == .orderedSame }) {
      Defaults[.forYouDismissedSubs].append(subreddit)
    }
    Task { await ForYouEngine.shared.dismiss(subreddit) }
  }
}
