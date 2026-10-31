import Foundation
import Synchronization
import Testing
@testable import HelioKit

struct WebSessionTests {
  /// An unsigned JWT with `claims` as its payload.
  private func jwt(_ claims: [String: Any]) throws -> String {
    let payload = try JSONSerialization.data(withJSONObject: claims).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    return "eyJhbGciOiJSUzI1NiJ9.\(payload).signature"
  }

  private func cookie(_ name: String, _ value: String, domain: String = ".reddit.com") throws -> HTTPCookie {
    try #require(HTTPCookie(properties: [.name: name, .value: value, .domain: domain, .path: "/"]))
  }

  @Test func tokenSubjectTellsSignedOutFromUnreadable() throws {
    #expect(try RedditWebSession.tokenSubject(jwt(["sub": "loid", "exp": 1])) == .signedOut)
    #expect(try RedditWebSession.tokenSubject(jwt(["sub": "t2_placeholder", "exp": 1])) == .account)
    // A token Helio can't read mustn't sign the user out.
    #expect(try RedditWebSession.tokenSubject(jwt(["exp": 1])) == .unknown)
    #expect(RedditWebSession.tokenSubject("not-a-jwt") == .unknown)
  }

  @Test func renewedCookiesReplaceAndExpireStoredOnes() throws {
    let renewed = try cookie("reddit_session", "renewed-session")
    let expired = try #require(HTTPCookie(properties: [
      .name: "token_v2", .value: "gone", .domain: ".reddit.com", .path: "/", .expires: Date(timeIntervalSince1970: 0),
    ]))
    let added = try cookie("edgebucket", "placeholder-bucket")
    let merged = RedditWebSession.merging("reddit_session=old; token_v2=stale; loid=placeholder", with: [renewed, expired, added])
    #expect(merged == "loid=placeholder; reddit_session=renewed-session; edgebucket=placeholder-bucket")
    #expect(RedditWebSession.merging("reddit_session=a=b", with: []) == "reddit_session=a=b")
  }

  @Test func cookieHeaderKeepsOnlyRedditCookies() throws {
    let header = try RedditWebSession.cookieHeader(from: [
      cookie("reddit_session", "placeholder-session"),
      cookie("loid", "placeholder-loid", domain: "www.reddit.com"),
      cookie("tracker", "elsewhere", domain: ".notreddit.com"),
    ])
    #expect(header == "reddit_session=placeholder-session; loid=placeholder-loid")
  }

  @Test func cookieHeaderNeedsTheSessionCookie() throws {
    #expect(try RedditWebSession.cookieHeader(from: [cookie("loid", "placeholder-loid")]) == nil)
  }

  @Test func webSessionCredentialRoundTripsAndRenewsWithItsCookies() throws {
    var credential = RedditCredential()
    credential.signInMethod = .webSession
    credential.webSessionCookies = "reddit_session=placeholder"
    #expect(credential.validationStatus == .authorized)
    #expect(credential.renewalKey == "reddit_session=placeholder")

    let decoded = try JSONDecoder().decode(RedditCredential.self, from: JSONEncoder().encode(credential))
    #expect(decoded.isWebSession)
    #expect(decoded.webSessionCookies == "reddit_session=placeholder")

    // A session Reddit signed out waits for the user to sign in again.
    credential.webSessionCookies = nil
    #expect(credential.validationStatus == .valid)
    #expect(credential.renewalKey == nil)
  }

  @Test func credentialsSavedBeforeWebSessionsDecodeAsAPIKeys() throws {
    let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","apiAppID":"placeholder-app-id","apiAppSecret":"","refreshToken":"placeholder-refresh"}"#
    let credential = try JSONDecoder().decode(RedditCredential.self, from: Data(json.utf8))
    #expect(credential.signInMethod == .apiKey)
    #expect(credential.renewalKey == "placeholder-refresh")
  }
}

struct RateLimitTests {
  private final class Clock: Sendable {
    let time = Mutex(Date(timeIntervalSince1970: 1_000_000))
    var now: Date {
      time.withLock { $0 }
    }

    func advance(_ seconds: TimeInterval) {
      time.withLock { $0 += seconds }
    }
  }

  private func response(_ status: Int, _ headers: [String: String], host: String = "oauth.reddit.com") throws -> HTTPURLResponse {
    try #require(HTTPURLResponse(url: URL(string: "https://\(host)/r/pics/hot")!, statusCode: status, httpVersion: nil, headerFields: headers))
  }

  @Test func spentBudgetHoldsRequestsUntilTheWindowResets() throws {
    let clock = Clock()
    let limit = RedditRateLimit(now: { clock.now })
    let account = UUID()
    try limit.record(response(200, ["x-ratelimit-remaining": "99.0", "x-ratelimit-reset": "300"]), account: account)
    #expect(limit.limitedUntil(account: account) == nil)
    #expect(!limit.isLow(account: account))

    try limit.record(response(200, ["x-ratelimit-remaining": "4.0", "x-ratelimit-reset": "200"]), account: account)
    #expect(limit.isLow(account: account))

    try limit.record(response(429, ["x-ratelimit-reset": "120"]), account: account)
    #expect(limit.limitedUntil(account: account) == clock.now.addingTimeInterval(120))
    // Other accounts have their own budget.
    #expect(limit.limitedUntil(account: UUID()) == nil)

    clock.advance(121)
    #expect(limit.limitedUntil(account: account) == nil)
    #expect(!limit.isLow(account: account))
  }

  @Test func onlyRedditAPIResponsesCount() throws {
    let limit = RedditRateLimit()
    try limit.record(response(429, [:], host: "api.streamable.com"), account: nil)
    #expect(limit.limitedUntil(account: nil) == nil)
    try limit.record(response(429, [:]), account: nil)
    #expect(limit.limitedUntil(account: nil) != nil)
  }

  @Test func retryTextRoundsUpToWholeMinutes() {
    let now = Date()
    #expect(RedditRateLimit.retryText(until: now.addingTimeInterval(61), now: now) == "Reddit's rate limit was reached. Try again in 2 min.")
    #expect(RedditRateLimit.retryText(until: now.addingTimeInterval(5), now: now) == "Reddit's rate limit was reached. Try again in 1 min.")
  }
}
