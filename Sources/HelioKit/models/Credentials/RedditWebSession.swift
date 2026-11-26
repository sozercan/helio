import Alamofire
import Foundation
import os
import Synchronization

enum RedditWebSession {
  static let clientID = "0R-WAMhuoo-MyQ"
  static let loginURL = URL(string: "https://www.reddit.com/login")!
  static let tokenURL = "https://accounts.reddit.com/api/access_token"
  static let sessionCookieName = "reddit_session"

  private static let logger = Logger(subsystem: "com.sertacozercan.helio", category: "WebSession")

  static let failedMintCooldown: TimeInterval = 30
  private static let failedMints = Mutex<[String: Date]>([:])

  enum MintResult: Equatable {
    case token(RedditCredential.AccessToken, cookies: String)
    case signedOut
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
        logger.notice("Token service returned a signed-out token; the web session ended")
        return .signedOut
      case .unknown:
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

  static func tokenSubject(_ token: String) -> TokenSubject {
    guard let subject = jwtClaims(token)?["sub"] as? String else { return .unknown }
    return subject.hasPrefix("loid") ? .signedOut : .account
  }

  static func isCurrentClientToken(_ token: String) -> Bool {
    guard let cid = jwtClaims(token)?["cid"] as? String else { return true }
    return cid == clientID
  }

  private static func jwtClaims(_ token: String) -> [String: Any]? {
    let parts = token.split(separator: ".")
    guard parts.count >= 2 else { return nil }
    var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
    guard let data = Data(base64Encoded: payload) else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  }

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

  private static func redditCookies(_ cookies: [HTTPCookie]) -> [HTTPCookie] {
    cookies.filter { cookie in
      let domain = cookie.domain.lowercased()
      return domain == "reddit.com" || domain.hasSuffix(".reddit.com")
    }
  }

  static func sessionCookieValue(from cookies: [HTTPCookie]) -> String? {
    redditCookies(cookies).first { $0.name == sessionCookieName && !$0.value.isEmpty }?.value
  }

  static func cookieHeader(from cookies: [HTTPCookie]) -> String? {
    guard sessionCookieValue(from: cookies) != nil else { return nil }
    return redditCookies(cookies).map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
  }

  enum SignInResult {
    case signedIn(RedditCredential)
    case signedOut
    case failed
  }

  static func signIn(_ credential: RedditCredential, cookies: String, userAgent: String) async -> SignInResult {
    var signedIn = credential
    signedIn.apiAppID = ""
    signedIn.apiAppSecret = ""
    signedIn.clearIdentity()
    signedIn.signInMethod = .webSession
    signedIn.webSessionCookies = cookies
    signedIn.userAgent = userAgent

    let token: RedditCredential.AccessToken
    let renewedCookies: String
    switch await mintToken(cookies: cookies, userAgent: userAgent) {
    case let .token(minted, cookies):
      token = minted
      renewedCookies = cookies
    case .signedOut:
      return .signedOut
    case .failed:
      return .failed
    }
    signedIn.accessToken = token
    signedIn.webSessionCookies = renewedCookies
    let me = await RedditAPI.shared.doRequest("\(RedditAPI.redditApiURLBase)/api/v1/me", method: .get, decodable: UserData.self, altCredential: signedIn, saveToken: false)
    guard case let .success(me) = me else { return .failed }
    signedIn.setProfile(from: me)
    return .signedIn(signedIn)
  }
}
