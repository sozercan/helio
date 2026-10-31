//
//  AccessTokenRefresher.swift
//  Helio
//

import Foundation

/// Runs one token refresh per refresh token at a time. Requests that find the token expired
/// together (a launch fires several) join the refresh in flight instead of each spending one,
/// and requests made before the new token reaches `RedditCredentialsManager` (a main-queue hop
/// later) reuse it.
actor AccessTokenRefresher {
  static let shared = AccessTokenRefresher()

  /// A forced renewal (after a 401) reuses a token refreshed this recently: the 401 came from a
  /// request that still carried the old one.
  static let forcedReuseWindow: TimeInterval = 30

  private var inFlight: [String: Task<RedditCredential.AccessToken?, Never>] = [:]
  private var latest: [String: RedditCredential.AccessToken] = [:]

  func token(refreshToken: String, forceRenew: Bool, refresh: @escaping @Sendable () async -> RedditCredential.AccessToken?) async -> RedditCredential.AccessToken? {
    if let task = inFlight[refreshToken] {
      return await task.value
    }
    if let token = latest[refreshToken], token.isFresh, !forceRenew || Date().timeIntervalSince(token.lastRefresh) < Self.forcedReuseWindow {
      return token
    }
    let task = Task { await refresh() }
    inFlight[refreshToken] = task
    let token = await task.value
    inFlight[refreshToken] = nil
    latest[refreshToken] = token
    return token
  }
}
