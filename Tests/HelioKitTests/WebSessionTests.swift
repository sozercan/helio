import Foundation
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

  @Test func signedOutTokensAreRecognized() throws {
    #expect(try RedditWebSession.isSignedOutToken(jwt(["sub": "loid", "exp": 1])))
    #expect(try !RedditWebSession.isSignedOutToken(jwt(["sub": "t2_placeholder", "exp": 1])))
    #expect(RedditWebSession.isSignedOutToken("not-a-jwt"))
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
