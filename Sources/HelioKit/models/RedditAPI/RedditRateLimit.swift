import Alamofire
import Foundation
import Synchronization

final class RedditRateLimit: Sendable {
  static let shared = RedditRateLimit()

  static let lowRemaining: Double = 10
  static let defaultHold: TimeInterval = 60

  private struct Budget {
    var remaining: Double
    var resetsAt: Date
  }

  private struct Key: Hashable {
    let account: UUID?
    let authorization: RedditCredential.AuthorizationID?
  }

  private let budgets = Mutex<[Key: Budget]>([:])
  private let now: @Sendable () -> Date

  init(now: @escaping @Sendable () -> Date = { Date() }) {
    self.now = now
  }

  private static func isRedditAPIHost(_ host: String?) -> Bool {
    guard let host = host?.lowercased() else { return false }
    return host == "oauth.reddit.com" || host == "www.reddit.com" || host == "old.reddit.com" || host == "api.reddit.com"
  }

  func record(_ response: HTTPURLResponse?, account: UUID?, authorization: RedditCredential.AuthorizationID? = nil) {
    let key = Key(account: account, authorization: authorization)
    guard let response, Self.isRedditAPIHost(response.url?.host) else { return }
    let limited = response.statusCode == 429
    let remaining = response.value(forHTTPHeaderField: "x-ratelimit-remaining").flatMap(Double.init)
    let reset = response.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(TimeInterval.init)
    guard limited || remaining != nil else { return }
    let now = now()
    var budget = Budget(remaining: limited ? 0 : remaining ?? 0, resetsAt: now.addingTimeInterval(reset ?? Self.defaultHold))
    budgets.withLock { budgets in
      if let known = budgets[key], known.resetsAt > now, budget.resetsAt <= known.resetsAt.addingTimeInterval(Self.sameWindowSlack) {
        budget.remaining = min(budget.remaining, known.remaining)
        budget.resetsAt = max(budget.resetsAt, known.resetsAt)
      }
      budgets[key] = budget
    }
  }

  static let sameWindowSlack: TimeInterval = 5

  func recording<T>(_ response: DataResponse<T, AFError>, account: UUID?, authorization: RedditCredential.AuthorizationID? = nil) -> Result<T, AFError> {
    record(response.response, account: account, authorization: authorization)
    return response.result
  }

  func limitedUntil(account: UUID?, authorization: RedditCredential.AuthorizationID? = nil) -> Date? {
    guard let budget = currentBudget(account, authorization: authorization), budget.remaining < 1 else { return nil }
    return budget.resetsAt
  }

  func isLow(account: UUID?, authorization: RedditCredential.AuthorizationID? = nil) -> Bool {
    guard let budget = currentBudget(account, authorization: authorization) else { return false }
    return budget.remaining < Self.lowRemaining
  }

  private func currentBudget(_ account: UUID?, authorization: RedditCredential.AuthorizationID?) -> Budget? {
    let key = Key(account: account, authorization: authorization)
    let now = now()
    return budgets.withLock { budgets in
      guard let budget = budgets[key], budget.resetsAt > now else { return nil }
      return budget
    }
  }

  static let limitedError = AFError.responseValidationFailed(reason: .unacceptableStatusCode(code: 429))

  static func retryText(until date: Date, now: Date = Date()) -> String {
    let minutes = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
    return "Reddit's rate limit was reached. Try again in \(minutes) min."
  }
}
