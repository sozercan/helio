import Foundation

/// Single-flight refresh per OAuth client/grant, including duplicate saved credential records.
/// A waiter owns its persistence policy; cancelling one waiter does not cancel the shared refresh.
actor AccessTokenRefresher {
  static let shared = AccessTokenRefresher()

  enum Outcome: Sendable {
    case token(RedditCredential.AccessToken)
    case webSessionToken(RedditCredential.AccessToken, cookies: String)
    case rejected
    case failed

    var accessToken: RedditCredential.AccessToken? {
      switch self {
      case let .token(token), let .webSessionToken(token, _): token
      case .rejected, .failed: nil
      }
    }
  }

  private var inFlight: [Data: Task<Outcome, Never>] = [:]
  private var latest: [Data: Outcome] = [:]

  /// A known rejected token is never reused. A forced renewal can share a newer token.
  func refresh(for authorization: RedditCredential.AuthorizationID, forceRenew: Bool, rejected: String? = nil,
               refresh: @escaping @Sendable () async -> Outcome) async -> Outcome
  {
    let grant = authorization.grantID
    if let task = inFlight[grant] {
      let outcome = await task.value
      if let token = outcome.accessToken, token.token == rejected {
        return .failed
      }
      return outcome
    }
    if let cached = latest[grant], let token = cached.accessToken, token.isFresh, token.token != rejected, !forceRenew || rejected != nil {
      return cached
    }
    let task = Task { await refresh() }
    inFlight[grant] = task
    let outcome = await task.value
    inFlight[grant] = nil
    if let token = outcome.accessToken, token.token == rejected {
      latest[grant] = nil
      return .failed
    }
    latest[grant] = outcome.accessToken == nil ? nil : outcome
    return outcome
  }
}
