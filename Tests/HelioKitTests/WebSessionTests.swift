import Alamofire
import Foundation
import Synchronization
import Testing
@testable import HelioKit

struct WebSessionTests {
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
    #expect(try RedditWebSession.tokenSubject(jwt(["exp": 1])) == .unknown)
    #expect(RedditWebSession.tokenSubject("not-a-jwt") == .unknown)
  }

  @Test func isCurrentClientTokenRejectsOtherClientIDs() throws {
    #expect(try RedditWebSession.isCurrentClientToken(jwt(["cid": RedditWebSession.clientID])))
    #expect(try !RedditWebSession.isCurrentClientToken(jwt(["cid": "old-client-id"])))
    #expect(try RedditWebSession.isCurrentClientToken(jwt(["sub": "t2_placeholder"])))
    #expect(RedditWebSession.isCurrentClientToken("not-a-jwt"))
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

  @Test func sessionCookieValueIgnoresOtherSitesAndEmptyValues() throws {
    #expect(try RedditWebSession.sessionCookieValue(from: [cookie("reddit_session", "placeholder-session")]) == "placeholder-session")
    #expect(try RedditWebSession.sessionCookieValue(from: [cookie("reddit_session", "elsewhere", domain: ".notreddit.com")]) == nil)
    #expect(try RedditWebSession.sessionCookieValue(from: [cookie("reddit_session", "")]) == nil)
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

private class WebSessionRoutingProtocol: URLProtocol, @unchecked Sendable {
  static let requests = Mutex<[URLRequest]>([])
  static let responseBody = Mutex<Data>(Data(#"{"kind":"Listing","data":{"children":[],"after":null}}"#.utf8))
  static let statusCode = Mutex<Int>(200)

  override class func canInit(with _: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    Self.requests.withLock { $0.append(request) }
    let code = Self.statusCode.withLock { $0 }
    let body = Self.responseBody.withLock { $0 }
    let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Suite(.serialized)
struct WebSessionRoutingTests {
  private func webAccount() -> RedditCredential {
    var credential = RedditCredential(
      accessToken: "placeholder-desktop-bearer",
      expiration: 3600,
      lastRefresh: Date(),
      userName: "placeholder-user",
    )
    credential.signInMethod = .webSession
    credential.webSessionCookies = "reddit_session=placeholder-session; token_v2=placeholder-v2"
    credential.userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Safari/605.1.15"
    return credential
  }

  private func apiAccount() -> RedditCredential {
    RedditCredential(
      apiAppID: "placeholder-client-id",
      accessToken: "placeholder-api-bearer",
      refreshToken: "placeholder-refresh",
      expiration: 3600,
      lastRefresh: Date(),
      userName: "placeholder-user",
    )
  }

  private func session(body: String, statusCode: Int = 200) -> Session {
    WebSessionRoutingProtocol.requests.withLock { $0 = [] }
    WebSessionRoutingProtocol.responseBody.withLock { $0 = Data(body.utf8) }
    WebSessionRoutingProtocol.statusCode.withLock { $0 = statusCode }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [WebSessionRoutingProtocol.self]
    return Session(configuration: configuration)
  }

  @Test func webSessionCommentsRouteToWwwWithCookiesAndReferer() async throws {
    let account = webAccount()
    let api = RedditAPI(session: session(body: "[]"), currentAccount: { account })
    _ = await api.fetchPost(subreddit: "swift", postID: "t3_abc123")

    let request = try #require(WebSessionRoutingProtocol.requests.withLock { $0.first })
    #expect(request.url?.host == "www.reddit.com")
    #expect(request.url?.path == "/r/swift/comments/abc123.json")
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(request.value(forHTTPHeaderField: "Cookie") == account.webSessionCookies)
    #expect(request.value(forHTTPHeaderField: "Referer") == "https://www.reddit.com/")
    #expect(request.value(forHTTPHeaderField: "User-Agent") == account.userAgent)
    #expect(!request.httpShouldHandleCookies)
  }

  @Test func webSessionMoreChildrenInfoAndSearchUseCookiesOnOAuth() async throws {
    let account = webAccount()
    let moreAPI = RedditAPI(session: session(body: #"{"json":{"errors":[],"data":{"things":[]}}}"#), currentAccount: { account })
    _ = await moreAPI.fetchMoreReplies(comments: ["c1"], moreID: "m1", postFullname: "t3_abc123")
    let moreRequest = try #require(WebSessionRoutingProtocol.requests.withLock { $0.first })
    #expect(moreRequest.url?.host == "oauth.reddit.com")
    #expect(moreRequest.url?.path == "/api/morechildren.json")
    #expect(moreRequest.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(moreRequest.value(forHTTPHeaderField: "Cookie") == account.webSessionCookies)
    #expect(moreRequest.value(forHTTPHeaderField: "Referer") == "https://oauth.reddit.com/")

    let infoAPI = RedditAPI(session: session(body: #"{"data":{"children":[]}}"#), currentAccount: { account })
    _ = await infoAPI.fetchInfoThings(fullnames: ["t3_abc123"], subredditNames: [], account: account)
    let infoRequest = try #require(WebSessionRoutingProtocol.requests.withLock { $0.first })
    #expect(infoRequest.url?.host == "oauth.reddit.com")
    #expect(infoRequest.url?.path == "/api/info")
    #expect(infoRequest.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(infoRequest.value(forHTTPHeaderField: "Cookie") == account.webSessionCookies)
    #expect(infoRequest.value(forHTTPHeaderField: "Referer") == "https://oauth.reddit.com/")

    let searchAPI = RedditAPI(session: session(body: #"{"kind":"Listing","data":{"children":[],"after":null}}"#), currentAccount: { account })
    _ = await searchAPI.searchInSubreddit("swift", RedditAPI.AdvancedPostsSearch(subreddit: "swift", flairs: nil, searchQuery: "test", sortOption: .best))
    let searchRequest = try #require(WebSessionRoutingProtocol.requests.withLock { $0.first })
    #expect(searchRequest.url?.host == "oauth.reddit.com")
    #expect(searchRequest.url?.path == "/r/swift/search.json")
    #expect(searchRequest.value(forHTTPHeaderField: "Authorization") == nil)
    #expect(searchRequest.value(forHTTPHeaderField: "Cookie") == account.webSessionCookies)
    #expect(searchRequest.value(forHTTPHeaderField: "Referer") == "https://oauth.reddit.com/")
  }

  @Test func webSessionFeedsStillUseBearerOnOAuth() async throws {
    let account = webAccount()
    let api = RedditAPI(session: session(body: #"{"kind":"Listing","data":{"children":[],"after":null}}"#), currentAccount: { account })
    _ = await api.fetchSubPosts("/r/swift", limit: 15)

    let request = try #require(WebSessionRoutingProtocol.requests.withLock { $0.first })
    #expect(request.url?.host == "oauth.reddit.com")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer placeholder-desktop-bearer")
    #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
  }

  @Test func apiKeyCommentsStayOnOAuthWithBearer() async throws {
    let account = apiAccount()
    let api = RedditAPI(session: session(body: "[]"), currentAccount: { account })
    _ = await api.fetchPost(subreddit: "swift", postID: "t3_abc123")

    let request = try #require(WebSessionRoutingProtocol.requests.withLock { $0.first })
    #expect(request.url?.host == "oauth.reddit.com")
    #expect(request.url?.path == "/r/swift/comments/abc123.json")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer placeholder-api-bearer")
    #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
  }

  @Test func cookieRequest401DoesNotRetryAsBearerRenewal() async {
    let account = webAccount()
    let api = RedditAPI(session: session(body: "[]", statusCode: 401), currentAccount: { account })
    _ = await api.fetchPost(subreddit: "swift", postID: "t3_abc123")

    let count = WebSessionRoutingProtocol.requests.withLock { $0.count }
    #expect(count == 1)
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

    clock.advance(100)
    try limit.record(response(200, ["x-ratelimit-remaining": "4.0", "x-ratelimit-reset": "200"]), account: account)
    #expect(limit.isLow(account: account))

    clock.advance(80)
    try limit.record(response(429, ["x-ratelimit-reset": "120"]), account: account)
    #expect(limit.limitedUntil(account: account) == clock.now.addingTimeInterval(120))
    #expect(limit.limitedUntil(account: UUID()) == nil)

    clock.advance(121)
    #expect(limit.limitedUntil(account: account) == nil)
    #expect(!limit.isLow(account: account))
  }

  @Test func aSlowResponseDoesNotLiftALimitALaterOneHit() throws {
    let clock = Clock()
    let limit = RedditRateLimit(now: { clock.now })
    let account = UUID()
    try limit.record(response(429, ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "200"]), account: account)
    clock.advance(1)
    try limit.record(response(200, ["x-ratelimit-remaining": "3.0", "x-ratelimit-reset": "199"]), account: account)
    #expect(limit.limitedUntil(account: account) != nil)

    clock.advance(200)
    try limit.record(response(200, ["x-ratelimit-remaining": "99.0", "x-ratelimit-reset": "600"]), account: account)
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

  @Test func wwwRedditRateLimitResponsesCount() throws {
    let clock = Clock()
    let limit = RedditRateLimit(now: { clock.now })
    let account = UUID()
    try limit.record(response(429, ["x-ratelimit-reset": "90"], host: "www.reddit.com"), account: account)
    #expect(limit.limitedUntil(account: account) == clock.now.addingTimeInterval(90))
  }

  @Test func retryTextRoundsUpToWholeMinutes() {
    let now = Date()
    #expect(RedditRateLimit.retryText(until: now.addingTimeInterval(61), now: now) == "Reddit's rate limit was reached. Try again in 2 min.")
    #expect(RedditRateLimit.retryText(until: now.addingTimeInterval(5), now: now) == "Reddit's rate limit was reached. Try again in 1 min.")
  }
}
