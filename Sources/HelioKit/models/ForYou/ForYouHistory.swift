//
//  ForYouHistory.swift
//  Helio
//

import Defaults
import Foundation

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
  /// Posts kept per account.
  static let limit = 200
  /// Open at least this long to count: a quick look back out isn't interest.
  static let minSeconds: Double = 10

  /// When each post page now showing opened, by fullname.
  private static var openSince: [String: (Date, UUID)] = [:]

  static func began(_ post: Post) {
    guard Defaults[.forYouUsed], let name = post.data?.name,
          let account = RedditCredentialsManager.shared.selectedCredential?.id else { return }
    began(name, account: account, at: Date())
  }

  static func ended(_ post: Post) {
    guard let data = post.data else { return }
    ended(data.name, subreddit: data.subreddit, title: data.title, at: Date())
  }

  static func began(_ id: String, account: UUID, at date: Date) {
    openSince[id] = (date, account)
  }

  static func ended(_ id: String, subreddit: String, title: String, at date: Date) {
    guard let (since, account) = openSince.removeValue(forKey: id) else { return }
    // A page left open while the phone sleeps isn't read the whole time.
    let seconds = min(date.timeIntervalSince(since), maxSecondsPerVisit)
    record(ForYouOpenedPost(id: id, subreddit: subreddit, title: title, lastOpened: date, seconds: seconds), account: account)
  }

  /// The most one visit counts for.
  static let maxSecondsPerVisit: Double = 10 * 60

  /// Adds a visit, its `seconds` the time it was open, to the post's entry, moving it to the front.
  static func record(_ visit: ForYouOpenedPost, account: UUID) {
    var all = Defaults[.forYouOpenedPosts]
    var posts = all[account.uuidString] ?? []
    var entry = visit
    entry.seconds = max(0, visit.seconds)
    if let index = posts.firstIndex(where: { $0.id == visit.id }) {
      entry.seconds += posts.remove(at: index).seconds
    }
    posts.insert(entry, at: 0)
    all[account.uuidString] = Array(posts.prefix(limit))
    Defaults[.forYouOpenedPosts] = all
  }

  /// The posts `account` opened long enough to count, newest first.
  nonisolated static func read(account: UUID) -> [ForYouOpenedPost] {
    (Defaults[.forYouOpenedPosts][account.uuidString] ?? []).filter { $0.seconds >= minSeconds }
  }

  /// Erases `account`'s history, including the visits still open, so closing them doesn't
  /// write it back.
  static func forget(account: UUID) {
    openSince = openSince.filter { $0.value.1 != account }
    Defaults[.forYouOpenedPosts][account.uuidString] = nil
  }

  /// Erases every account's history, including the visits still open.
  static func clear() {
    openSince = [:]
    Defaults[.forYouOpenedPosts] = [:]
  }
}
