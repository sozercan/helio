//
//  RedditRateLimit.swift
//  Helio
//

import Alamofire
import Foundation
import Synchronization

/// Each account's Reddit request budget, from the `x-ratelimit-*` headers on its API responses.
/// Reddit counts requests per window and answers 429 to everything once the window's budget is
/// spent, so requests made then only fail.
final class RedditRateLimit: Sendable {
  static let shared = RedditRateLimit()

  /// Below this many requests left in the window, optional lookups (avatars) wait for the next one.
  static let lowRemaining: Double = 10
  /// How long a 429 without a reset time holds requests back.
  static let defaultHold: TimeInterval = 60

  private struct Budget {
    var remaining: Double
    var resetsAt: Date
  }

  private let budgets = Mutex<[UUID?: Budget]>([:])
  private let now: @Sendable () -> Date

  init(now: @escaping @Sendable () -> Date = { Date() }) {
    self.now = now
  }

  /// Notes the budget an `oauth.reddit.com` response reports for `account`.
  func record(_ response: HTTPURLResponse?, account: UUID?) {
    guard let response, response.url?.host == "oauth.reddit.com" else { return }
    let limited = response.statusCode == 429
    let remaining = response.value(forHTTPHeaderField: "x-ratelimit-remaining").flatMap(Double.init)
    let reset = response.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(TimeInterval.init)
    guard limited || remaining != nil else { return }
    let now = now()
    var budget = Budget(remaining: limited ? 0 : remaining ?? 0, resetsAt: now.addingTimeInterval(reset ?? Self.defaultHold))
    budgets.withLock { budgets in
      // Responses can arrive out of order, and within a window the budget only goes down: a
      // slow response mustn't lift a limit a later one hit. A reset well after the known one
      // starts a new window.
      if let known = budgets[account], known.resetsAt > now, budget.resetsAt <= known.resetsAt.addingTimeInterval(Self.sameWindowSlack) {
        budget.remaining = min(budget.remaining, known.remaining)
        budget.resetsAt = max(budget.resetsAt, known.resetsAt)
      }
      budgets[account] = budget
    }
  }

  /// How far apart two responses' reset times can be and still belong to the same window: the
  /// header is in whole seconds and responses take a while to arrive.
  static let sameWindowSlack: TimeInterval = 5

  func recording<T>(_ response: DataResponse<T, AFError>, account: UUID?) -> Result<T, AFError> {
    record(response.response, account: account)
    return response.result
  }

  /// When `account` can make requests again, or `nil` while it can now.
  func limitedUntil(account: UUID?) -> Date? {
    guard let budget = currentBudget(account), budget.remaining < 1 else { return nil }
    return budget.resetsAt
  }

  /// Whether `account` is close to spending this window's budget.
  func isLow(account: UUID?) -> Bool {
    guard let budget = currentBudget(account) else { return false }
    return budget.remaining < Self.lowRemaining
  }

  private func currentBudget(_ account: UUID?) -> Budget? {
    let now = now()
    return budgets.withLock { budgets in
      guard let budget = budgets[account], budget.resetsAt > now else { return nil }
      return budget
    }
  }

  /// The error a request held back by the rate limit fails with, the same as Reddit's 429.
  static let limitedError = AFError.responseValidationFailed(reason: .unacceptableStatusCode(code: 429))

  /// "Try again in 3 min" text for a limit that lifts at `date`.
  static func retryText(until date: Date, now: Date = Date()) -> String {
    let minutes = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
    return "Reddit's rate limit was reached. Try again in \(minutes) min."
  }
}
