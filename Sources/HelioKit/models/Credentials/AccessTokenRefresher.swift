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

  private var inFlight: [String: Task<RedditCredential.AccessToken?, Never>] = [:]
  private var latest: [String: RedditCredential.AccessToken] = [:]

  /// `forceRenew` with `rejected`, the token a request was just refused with: the latest token is
  /// reused only when it's a different one, since the request then carried an older token.
  func token(refreshToken: String, forceRenew: Bool, rejected: String? = nil,
             refresh: @escaping @Sendable () async -> RedditCredential.AccessToken?) async -> RedditCredential.AccessToken?
  {
    if let task = inFlight[refreshToken] {
      return await task.value
    }
    if let token = latest[refreshToken], token.isFresh, !forceRenew || (rejected != nil && token.token != rejected) {
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
