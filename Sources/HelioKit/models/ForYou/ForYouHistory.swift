//
//  ForYouHistory.swift
//  Helio
//

import CryptoKit
import Defaults
import Foundation
import UIKit

/// A post the account opened, for For You: its subreddit and title, and how long it stayed open.
struct ForYouOpenedPost: Codable, Hashable, Sendable, Defaults.Serializable {
  /// The post's fullname.
  let id: String
  let subreddit: String
  let title: String
  var lastOpened: Date
  var seconds: Double
}

/// The posts each account opened, newest first, kept on this device for For You, which counts the
/// ones read for a while as interest the way Reddit counts views. Recorded only once For You has
/// been used, and cleared with the account.
@MainActor
enum ForYouHistory {
  /// Whose history a visit goes to: the Reddit account signed in on a credential. Signing in to
  /// another account on the same credential starts another history. The account's name is
  /// kept only as a hash.
  struct Owner: Hashable, Sendable {
    let credentialID: UUID
    let account: String

    nonisolated init(_ credential: RedditCredential) {
      credentialID = credential.id
      let name = (credential.userName ?? "").lowercased()
      account = SHA256.hash(data: Data(name.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated init(credentialID: UUID, account: String) {
      self.credentialID = credentialID
      self.account = account
    }

    nonisolated var key: String {
      "\(credentialID.uuidString)|\(account)"
    }
  }

  /// One post page's stay, counting only the time its window was in front.
  struct Visit {
    let post: String
    let owner: Owner
    /// When the current stretch in front began; nil while its window is in the background.
    var since: Date?
    /// The time of earlier stretches not yet recorded.
    var seconds: Double = 0
    /// The time already recorded, from when its window went to the background.
    var recorded: Double = 0

    func unrecorded(at date: Date) -> Double {
      seconds + (since.map { date.timeIntervalSince($0) } ?? 0)
    }
  }

  /// Posts kept per account.
  static let limit = 200
  /// Open at least this long to count: a quick look back out isn't interest.
  static let minSeconds: Double = 10
  /// The most one visit counts for: a page left showing isn't necessarily read the whole time.
  static let maxSecondsPerVisit: Double = 10 * 60

  /// The post pages now showing, each by its own token: the same post can show in two windows.
  private static var visits: [UUID: Visit] = [:]
  private static var observesAppState = false

  /// Starts timing a post page; nil when nothing's recorded. A post opened from a link has no
  /// details yet, so it's known by its fullname until they load.
  static func began(_ post: Post) -> UUID? {
    guard Defaults[.forYouUsed], let credential = RedditCredentialsManager.shared.selectedCredential else { return nil }
    observeAppStateIfNeeded()
    return began(post.fullname, owner: Owner(credential), at: Date())
  }

  /// Saves the posts shown when Helio goes to the background, where it may be ended.
  private static func observeAppStateIfNeeded() {
    guard !observesAppState else { return }
    observesAppState = true
    NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
      MainActor.assumeIsolated { saveShown() }
    }
  }

  /// Stops the clock of a visit while its window is in the background, as with the phone locked,
  /// and records the time so far: the app may be ended there.
  static func paused(_ token: UUID, post: Post) {
    paused(token, details: post.data.map { ($0.subreddit, $0.title) }, at: Date())
  }

  static func paused(_ token: UUID, details: (subreddit: String, title: String)?, at date: Date) {
    guard var visit = visits[token], visit.since != nil else { return }
    visit.seconds = visit.unrecorded(at: date)
    visit.since = nil
    if let details, visit.seconds > 0 {
      recordTime(of: &visit, subreddit: details.subreddit, title: details.title, at: date)
    }
    visits[token] = visit
  }

  static func resumed(_ token: UUID, at date: Date = Date()) {
    if visits[token]?.since == nil {
      visits[token]?.since = date
    }
  }

  /// Records the visit `token` started, if the post's details loaded by then.
  static func ended(_ token: UUID, post: Post) {
    guard let data = post.data else {
      visits[token] = nil
      return
    }
    ended(token, subreddit: data.subreddit, title: data.title, at: Date())
  }

  static func began(_ post: String, owner: Owner, at date: Date) -> UUID {
    let token = UUID()
    visits[token] = Visit(post: post, owner: owner, since: date)
    return token
  }

  static func ended(_ token: UUID, subreddit: String, title: String, at date: Date) {
    guard var visit = visits.removeValue(forKey: token) else { return }
    visit.seconds = visit.unrecorded(at: date)
    recordTime(of: &visit, subreddit: subreddit, title: title, at: date)
  }

  /// Adds a visit's time not yet recorded to its post's entry, up to `maxSecondsPerVisit` in all.
  private static func recordTime(of visit: inout Visit, subreddit: String, title: String, at date: Date) {
    let seconds = max(0, min(visit.seconds, maxSecondsPerVisit - visit.recorded))
    record(ForYouOpenedPost(id: visit.post, subreddit: subreddit, title: title, lastOpened: date, seconds: seconds), owner: visit.owner)
    visit.recorded += seconds
    visit.seconds = 0
  }

  /// Adds a visit, its `seconds` the time it was open, to the post's entry, moving it to the front.
  static func record(_ visit: ForYouOpenedPost, owner: Owner) {
    var all = Defaults[.forYouOpenedPosts]
    var posts = all[owner.key] ?? []
    var entry = visit
    entry.seconds = max(0, visit.seconds)
    if let index = posts.firstIndex(where: { $0.id == visit.id }) {
      entry.seconds += posts.remove(at: index).seconds
    }
    posts.insert(entry, at: 0)
    all[owner.key] = Array(posts.prefix(limit))
    Defaults[.forYouOpenedPosts] = all
  }

  /// The posts `owner` opened long enough to count, newest first.
  nonisolated static func read(_ owner: Owner) -> [ForYouOpenedPost] {
    (Defaults[.forYouOpenedPosts][owner.key] ?? []).filter { $0.seconds >= minSeconds }
  }

  // MARK: Shown in For You

  /// How long a post For You showed stays out of it: like Reddit's, For You doesn't show a post
  /// again once it has.
  static let shownFor: TimeInterval = 7 * 24 * 60 * 60
  /// Posts kept per account.
  static let shownLimit = 3000

  /// Loaded on first use and saved a few seconds after it changes, as rows show often.
  private static var shownCache: [String: [String: Date]]?
  private static var saveScheduled = false

  private static var shownPosts: [String: [String: Date]] {
    if let shownCache {
      return shownCache
    }
    let loaded = Defaults[.forYouShownPosts]
    shownCache = loaded
    return loaded
  }

  /// Notes that For You showed `post` to `owner`, when it first did.
  static func shown(_ post: String, owner: Owner, at date: Date = Date()) {
    var all = shownPosts
    // Kept from when it first showed, until that's a week old: then it showed afresh.
    if let shownAt = all[owner.key]?[post], date.timeIntervalSince(shownAt) < shownFor {
      return
    }
    all[owner.key, default: [:]][post] = date
    shownCache = all
    observeAppStateIfNeeded()
    guard !saveScheduled else { return }
    saveScheduled = true
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(5))
      saveShown()
    }
  }

  /// Saves the posts shown, keeping a week's and at most `shownLimit` per account.
  static func saveShown(now: Date = Date()) {
    saveScheduled = false
    guard var all = shownCache else { return }
    for (key, posts) in all {
      let recent = posts.filter { now.timeIntervalSince($0.value) < shownFor }
      all[key] = recent.count > shownLimit
        ? Dictionary(uniqueKeysWithValues: recent.sorted { $0.value > $1.value }.prefix(shownLimit).map { ($0.key, $0.value) })
        : recent
    }
    all = all.filter { !$0.value.isEmpty }
    shownCache = all
    Defaults[.forYouShownPosts] = all
  }

  /// The posts `owner` already saw, by fullname: shown in For You in the last week, or opened.
  /// For You leaves them out.
  static func seen(_ owner: Owner, now: Date = Date()) -> Set<String> {
    let shown = (shownPosts[owner.key] ?? [:]).filter { now.timeIntervalSince($0.value) < shownFor }.keys
    let opened = (Defaults[.forYouOpenedPosts][owner.key] ?? []).map(\.id)
    // Open now, in this window or another, though not recorded until it closes.
    let open = visits.values.filter { $0.owner == owner }.map(\.post)
    return Set(shown).union(opened).union(open)
  }

  // MARK: Erasing

  /// Erases the history of every account signed in on `credentialID`, including the visits still
  /// open, so closing them doesn't write it back.
  static func forget(credentialID: UUID) {
    visits = visits.filter { $0.value.owner.credentialID != credentialID }
    let prefix = "\(credentialID.uuidString)|"
    // Early builds kept a credential's history under its bare id.
    Defaults[.forYouOpenedPosts] = Defaults[.forYouOpenedPosts].filter { !$0.key.hasPrefix(prefix) && $0.key != credentialID.uuidString }
    shownCache = shownPosts.filter { !$0.key.hasPrefix(prefix) }
    Defaults[.forYouShownPosts] = shownCache ?? [:]
  }

  /// Erases every account's history, including the visits still open.
  static func clear() {
    visits = [:]
    Defaults[.forYouOpenedPosts] = [:]
    shownCache = [:]
    Defaults[.forYouShownPosts] = [:]
  }
}
