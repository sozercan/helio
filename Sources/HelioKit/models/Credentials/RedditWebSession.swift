//
//  RedditWebSession.swift
//  Helio
//

import Alamofire
import Foundation
import os

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

  enum MintResult: Equatable {
    case token(RedditCredential.AccessToken)
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
    let result = await RedditAPI.shared._doRequest(authenticated: false) { _ in
      var headers: HTTPHeaders = ["User-Agent": userAgent, "Cookie": cookies]
      headers.add(.authorization(username: clientID, password: ""))
      return await AF.request(
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
      .serializingDecodable(TokenResponse.self).response.result
    }

    switch result {
    case let .success(data):
      // A signed-out session still gets a token, for an anonymous visitor.
      guard !isSignedOutToken(data.access_token) else {
        logger.notice("Token service returned a signed-out token; the web session ended")
        return .signedOut
      }
      return .token(.init(token: data.access_token, expiration: data.expires_in, lastRefresh: Date()))
    case let .failure(error):
      if error.responseCode == 401 {
        logger.notice("Token service refused the web session (401)")
        return .signedOut
      }
      logger.error("Web session token request failed: \(error.localizedDescription, privacy: .public)")
      return .failed
    }
  }

  /// Whether a bearer belongs to a signed-out visitor: its JWT subject is a logged-out id
  /// (`loid`) instead of an account.
  static func isSignedOutToken(_ token: String) -> Bool {
    let parts = token.split(separator: ".")
    guard parts.count >= 2 else { return true }
    var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
    guard
      let data = Data(base64Encoded: payload),
      let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let subject = claims["sub"] as? String
    else { return true }
    return subject.hasPrefix("loid")
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

    guard let token = await signedIn.getUpToDateToken(forceRenew: true, saveToken: false) else { return nil }
    signedIn.accessToken = token
    guard let me = await RedditAPI.shared.fetchMe(force: true, altCredential: signedIn, saveToken: false) else { return nil }
    signedIn.setProfile(from: me)
    return signedIn
  }
}
