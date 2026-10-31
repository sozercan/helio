//
//  RedditWebSession.swift
//  Helio
//

import Alamofire
import Foundation
import os
import Synchronization

/// Signing in without an API key. The user signs in on reddit.com (`RedditWebLoginView`), Helio
/// keeps the session's cookies, and it trades them for ~24 h OAuth bearer tokens at the token
/// service Reddit's mobile site uses. Those tokens work on the same `oauth.reddit.com` REST API
/// an API key's do.
enum RedditWebSession {
  /// The client id of Reddit's mobile web site. It has no secret and is sent with every
  /// signed-out reddit.com page load.
  static let clientID = "ohXpoqrZYub1kg"
  static let loginURL = URL(string: "https://www.reddit.com/login")!
  static let tokenURL = "https://accounts.reddit.com/api/access_token"
  /// The cookie that carries a reddit.com sign-in. Reddit sets it for signed-out visitors too, so
  /// its presence alone doesn't prove one.
  static let sessionCookieName = "reddit_session"

  private static let logger = Logger(subsystem: "com.sertacozercan.helio", category: "WebSession")

  /// How long a session whose token request failed waits before asking again. Without it every
  /// API request would ask anew while the token service is down or refusing.
  static let failedMintCooldown: TimeInterval = 30
  /// When each session's last token request failed, by its cookies.
  private static let failedMints = Mutex<[String: Date]>([:])

  enum MintResult: Equatable {
    /// `cookies`: the session's cookies with any Reddit renewed in the response.
    case token(RedditCredential.AccessToken, cookies: String)
    /// Reddit no longer recognizes the session: the user has to sign in again.
    case signedOut
    /// Anything else, such as a dropped connection. The session may still be good.
    case failed
  }

  private struct TokenResponse: Decodable {
    let access_token: String
    let expires_in: Int
  }

  static func mintToken(cookies: String, userAgent: String) async -> MintResult {
    if let failedAt = failedMints.withLock({ $0[cookies] }), Date().timeIntervalSince(failedAt) < failedMintCooldown {
      return .failed
    }
    let result = await requestToken(cookies: cookies, userAgent: userAgent)
    failedMints.withLock { failed in
      if result == .failed {
        failed[cookies] = Date()
      } else {
        failed[cookies] = nil
      }
    }
    return result
  }

  private static func requestToken(cookies: String, userAgent: String) async -> MintResult {
    var setCookies: [HTTPCookie] = []
    let result = await RedditAPI.shared._doRequest(authenticated: false) { _ in
      var headers: HTTPHeaders = ["User-Agent": userAgent, "Cookie": cookies]
      headers.add(.authorization(username: clientID, password: ""))
      let response = await AF.request(
        tokenURL,
        method: .post,
        parameters: ["scopes": ["*"]],
        encoder: JSONParameterEncoder.default,
        headers: headers,
        requestModifier: { request in
          // The session's cookies go in the header above, never into the shared cookie store.
          request.httpShouldHandleCookies = false
          request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        },
      )
      .validate()
      .serializingDecodable(TokenResponse.self).response
      if let fields = response.response?.headers.dictionary, let url = response.request?.url {
        setCookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
      }
      return response.result
    }

    switch result {
    case let .success(data):
      switch tokenSubject(data.access_token) {
      case .signedOut:
        // A signed-out session still gets a token, for an anonymous visitor.
        logger.notice("Token service returned a signed-out token; the web session ended")
        return .signedOut
      case .unknown:
        // Keeps the session: a token Helio can't read says nothing about it.
        logger.error("Token service returned a token Helio can't read")
        return .failed
      case .account:
        return .token(.init(token: data.access_token, expiration: data.expires_in, lastRefresh: Date()),
                      cookies: merging(cookies, with: setCookies))
      }
    case let .failure(error):
      if error.responseCode == 401 {
        logger.notice("Token service refused the web session (401)")
        return .signedOut
      }
      logger.error("Web session token request failed: \(error.localizedDescription, privacy: .public)")
      return .failed
    }
  }

  enum TokenSubject { case account, signedOut, unknown }

  /// Whom a bearer acts for, from its JWT subject: a signed-out visitor's is a logged-out id
  /// (`loid`) instead of an account.
  static func tokenSubject(_ token: String) -> TokenSubject {
    let parts = token.split(separator: ".")
    guard parts.count >= 2 else { return .unknown }
    var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
    guard
      let data = Data(base64Encoded: payload),
      let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let subject = claims["sub"] as? String
    else { return .unknown }
    return subject.hasPrefix("loid") ? .signedOut : .account
  }

  /// `header` with the cookies a response set: new values replace old ones, and cookies the
  /// response expired are dropped.
  static func merging(_ header: String, with setCookies: [HTTPCookie]) -> String {
    var pairs: [(name: String, value: String)] = header.split(separator: ";").compactMap { pair in
      let parts = pair.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
      guard parts.count == 2 else { return nil }
      return (String(parts[0]), String(parts[1]))
    }
    for cookie in setCookies {
      pairs.removeAll { $0.name == cookie.name }
      let expired = cookie.expiresDate.map { $0 <= Date() } ?? false
      if !expired, !cookie.value.isEmpty {
        pairs.append((cookie.name, cookie.value))
      }
    }
    return pairs.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
  }

  /// The reddit.com cookies as a `Cookie` header, or `nil` when the session cookie isn't among them.
  static func cookieHeader(from cookies: [HTTPCookie]) -> String? {
    let reddit = cookies.filter { cookie in
      let domain = cookie.domain.lowercased()
      return domain == "reddit.com" || domain.hasSuffix(".reddit.com")
    }
    guard reddit.contains(where: { $0.name == sessionCookieName && !$0.value.isEmpty }) else { return nil }
    return reddit.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
  }

  /// Turns `credential` into a web-session credential for the signed-in session and fills in its
  /// account. Returns `nil` when Reddit doesn't hand out a token for the session.
  static func signIn(_ credential: RedditCredential, cookies: String, userAgent: String) async -> RedditCredential? {
    var signedIn = credential
    // Clearing the API key first: changing it resets the identity set below.
    signedIn.apiAppID = ""
    signedIn.apiAppSecret = ""
    signedIn.clearIdentity()
    signedIn.signInMethod = .webSession
    signedIn.webSessionCookies = cookies
    signedIn.userAgent = userAgent

    guard case let .token(token, renewedCookies) = await mintToken(cookies: cookies, userAgent: userAgent) else { return nil }
    signedIn.accessToken = token
    signedIn.webSessionCookies = renewedCookies
    // Not `fetchMe`, which would also make this account the app's current one before it's saved.
    let me = await RedditAPI.shared.doRequest("\(RedditAPI.redditApiURLBase)/api/v1/me", method: .get, decodable: UserData.self, altCredential: signedIn, saveToken: false)
    guard case let .success(me) = me else { return nil }
    signedIn.setProfile(from: me)
    return signedIn
  }
}
