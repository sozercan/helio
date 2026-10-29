import Foundation
import Testing
@testable import HelioKit

struct AuthRedirectTests {
  @Test func authorizationURLUsesHTTPSRedirect() throws {
    let url = RedditAPI.shared.getAuthorizationCodeURL("client", state: "s")
    let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    let redirect = try #require(items.first { $0.name == "redirect_uri" }?.value)
    // Reddit rejects non-https redirects for keys with a secret.
    #expect(redirect == RedditAPI.appRedirectURI)
    #expect(URL(string: redirect)?.scheme == "https")
  }

  @Test func readsCodeFromForwardedCallback() {
    let callback = URL(string: "helioapp://auth-success?state=s&code=abc#_")!
    #expect(RedditAPI.authCode(from: callback, state: "s") == "abc")
    #expect(RedditAPI.authCode(from: callback, state: "other") == nil)
  }
}
