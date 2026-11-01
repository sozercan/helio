import Foundation
import Testing
@testable import HelioKit

struct WebAuthorizationOwnershipTests {
  private let originalCookies = "reddit_session=placeholder-original-session"
  private let renewedCookies = "reddit_session=placeholder-renewed-session"
  private let replacementCookies = "reddit_session=placeholder-replacement-session"

  private func webCredential() -> RedditCredential {
    var account = RedditCredential(userName: "placeholder-user")
    account.signInMethod = .webSession
    account.webSessionCookies = originalCookies
    return account
  }

  private func apiCredential() -> RedditCredential {
    RedditCredential(
      apiAppID: "placeholder-client-id", apiAppSecret: "placeholder-client-secret",
      refreshToken: "placeholder-refresh-token", userName: "placeholder-user",
    )
  }

  private func token(_ value: String, timestamp: TimeInterval) -> RedditCredential.AccessToken {
    .init(token: value, expiration: 3600, lastRefresh: Date(timeIntervalSince1970: timestamp))
  }

  @Test func webAuthorizationNeedsCookiesButNotAPIKeysOrAnAccessToken() throws {
    var account = webCredential()
    #expect(account.apiAppID.isEmpty)
    #expect(account.apiAppSecret.isEmpty)
    #expect(account.refreshToken == nil)
    #expect(account.accessToken == nil)
    let authorization = try #require(account.authorizationID)
    let sessionID = account.webSessionID

    account.accessToken = token("placeholder-first-access-token", timestamp: 100)
    #expect(account.authorizationID == authorization)
    account.accessToken = token("placeholder-newer-access-token", timestamp: 200)
    #expect(account.authorizationID == authorization)
    #expect(account.webSessionID == sessionID)

    account.webSessionCookies = nil
    #expect(account.authorizationID == nil)
  }

  @Test func webAuthorizationAndSessionIDSurviveCodableRoundTrip() throws {
    var account = webCredential()
    account.accessToken = token("placeholder-access-token", timestamp: 100)
    let authorization = try #require(account.authorizationID)
    let encoded = try JSONEncoder().encode(account)
    let stored = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let storedSessionID = try #require(stored["webSessionID"] as? String)
    #expect(UUID(uuidString: storedSessionID) == account.webSessionID)

    let decoded = try JSONDecoder().decode(RedditCredential.self, from: encoded)
    #expect(decoded == account)
    #expect(decoded.signInMethod == .webSession)
    #expect(decoded.webSessionID == account.webSessionID)
    #expect(decoded.authorizationID == authorization)
  }

  @Test func oldStoredWebRecordUsesCredentialIDAsDeterministicSessionID() throws {
    // A record saved before webSessionID existed, not a new record with the field removed.
    let json = """
    {"id":"00000000-0000-0000-0000-000000000001","apiAppID":"","apiAppSecret":"",\
    "signInMethod":"webSession","webSessionCookies":"reddit_session=placeholder-original-session",\
    "userName":"placeholder-user"}
    """
    let data = Data(json.utf8)
    let first = try JSONDecoder().decode(RedditCredential.self, from: data)
    let second = try JSONDecoder().decode(RedditCredential.self, from: data)
    let authorization = try #require(first.authorizationID)
    #expect(first.webSessionID == first.id)
    #expect(second.webSessionID == first.id)
    #expect(second.authorizationID == authorization)

    let roundTripped = try JSONDecoder().decode(RedditCredential.self, from: JSONEncoder().encode(first))
    #expect(roundTripped.webSessionID == first.id)
    #expect(roundTripped.authorizationID == authorization)
  }

  @Test(arguments: [false, true], [false, true])
  func directCookieReplacementRejectsOldResults(signedOut: Bool, restoreOriginalCookies: Bool) throws {
    var account = webCredential()
    let authorization = try #require(account.authorizationID)
    let sessionID = account.webSessionID
    account.webSessionCookies = replacementCookies
    #expect(account.webSessionID != sessionID)
    #expect(try #require(account.authorizationID) != authorization)

    // Even replacing A with B and then A again must not resurrect A's old grant.
    if restoreOriginalCookies {
      account.webSessionCookies = originalCookies
    }
    #expect(account.webSessionID != sessionID)
    #expect(try #require(account.authorizationID) != authorization)
    account.accessToken = token("placeholder-replacement-access-token", timestamp: 200)
    let before = account
    let delayedToken = signedOut ? nil : token("placeholder-delayed-access-token", timestamp: 300)
    let updated = account.updateWebAccessToken(
      delayedToken, cookies: renewedCookies, renewedFrom: originalCookies, for: authorization,
    )
    #expect(!updated)
    #expect(account == before)
  }

  @Test func cookieRenewalPreservesGrantAndCurrentMetadata() throws {
    var account = webCredential()
    let authorization = try #require(account.authorizationID)
    let sessionID = account.webSessionID
    account.userName = "placeholder-updated-user"
    account.userAgent = "placeholder-custom-agent"
    let firstToken = token("placeholder-first-access-token", timestamp: 100)
    let updated1 = account.updateWebAccessToken(
      firstToken, cookies: renewedCookies, renewedFrom: originalCookies, for: authorization,
    )
    #expect(updated1)
    #expect(account.accessToken == firstToken)
    #expect(account.webSessionCookies == renewedCookies)
    #expect(account.webSessionID == sessionID)
    #expect(account.authorizationID == authorization)

    let nextToken = token("placeholder-next-access-token", timestamp: 200)
    let updated2 = account.updateWebAccessToken(
      nextToken, cookies: replacementCookies, renewedFrom: renewedCookies, for: authorization,
    )
    #expect(updated2)
    #expect(account.accessToken == nextToken)
    #expect(account.webSessionCookies == replacementCookies)
    #expect(account.webSessionID == sessionID)
    #expect(account.authorizationID == authorization)
    #expect(account.userName == "placeholder-updated-user")
    #expect(account.userAgent == "placeholder-custom-agent")
  }

  @Test func olderTokenCannotReplaceMatchingCurrentCookieSnapshot() throws {
    var account = webCredential()
    let authorization = try #require(account.authorizationID)
    let updated3 = account.updateWebAccessToken(
      token("placeholder-newer-access-token", timestamp: 200), cookies: originalCookies,
      renewedFrom: originalCookies, for: authorization,
    )
    #expect(updated3)
    let before = account
    let acceptedOlder = account.updateWebAccessToken(
      token("placeholder-older-access-token", timestamp: 100), cookies: renewedCookies,
      renewedFrom: originalCookies, for: authorization,
    )
    #expect(!acceptedOlder)
    #expect(account == before)
  }

  @Test(arguments: [false, true])
  func delayedResultCannotReplaceRenewedCookieSnapshot(signedOut: Bool) throws {
    var account = webCredential()
    let authorization = try #require(account.authorizationID)
    let updated4 = account.updateWebAccessToken(
      token("placeholder-current-access-token", timestamp: 200), cookies: renewedCookies,
      renewedFrom: originalCookies, for: authorization,
    )
    #expect(updated4)
    #expect(account.authorizationID == authorization)
    let before = account
    // A later timestamp cannot compensate for minting against obsolete cookies.
    let delayedToken = signedOut ? nil : token("placeholder-delayed-access-token", timestamp: 300)
    let updated5 = account.updateWebAccessToken(
      delayedToken, cookies: replacementCookies, renewedFrom: originalCookies, for: authorization,
    )
    #expect(!updated5)
    #expect(account == before)
  }

  @Test func webResultCannotUpdateAnotherCredentialWithTheSameCookies() throws {
    let source = webCredential()
    let authorization = try #require(source.authorizationID)
    var other = source
    other.id = UUID()
    #expect(try #require(other.authorizationID) != authorization)
    let before = other
    let updated6 = other.updateWebAccessToken(
      token("placeholder-access-token", timestamp: 100), cookies: renewedCookies,
      renewedFrom: originalCookies, for: authorization,
    )
    #expect(!updated6)
    #expect(other == before)
  }

  @Test(arguments: [false, true])
  func apiTokenUpdaterCannotMutateWebAuthorization(signedOut: Bool) throws {
    var account = webCredential()
    let authorization = try #require(account.authorizationID)
    let before = account
    let result = signedOut ? nil : token("placeholder-api-access-token", timestamp: 100)
    let updated7 = account.updateAccessToken(result, for: authorization)
    #expect(!updated7)
    #expect(account == before)
  }

  @Test(arguments: [false, true])
  func webTokenUpdaterCannotMutateAPIAuthorization(signedOut: Bool) throws {
    var account = apiCredential()
    // Residual web fields must not make an API-key record accept a web result.
    account.webSessionCookies = originalCookies
    let authorization = try #require(account.authorizationID)
    let before = account
    let result = signedOut ? nil : token("placeholder-web-access-token", timestamp: 100)
    let updated8 = account.updateWebAccessToken(
      result, cookies: renewedCookies, renewedFrom: originalCookies, for: authorization,
    )
    #expect(!updated8)
    #expect(account == before)
  }

  @Test func changingSignInMethodChangesAuthorizationEvenWithBothGrantsPresent() throws {
    var account = apiCredential()
    account.webSessionCookies = originalCookies
    let apiAuthorization = try #require(account.authorizationID)
    account.signInMethod = .webSession
    let webAuthorization = try #require(account.authorizationID)
    #expect(webAuthorization != apiAuthorization)
    let before = account
    let updated9 = account.updateWebAccessToken(
      token("placeholder-access-token", timestamp: 100), cookies: renewedCookies,
      renewedFrom: originalCookies, for: apiAuthorization,
    )
    #expect(!updated9)
    #expect(account == before)
  }

  @Test func apiRenewalAndRejectionKeepTheirExistingIdentityAndNameBehavior() throws {
    var account = apiCredential()
    let authorization = try #require(account.authorizationID)
    let refreshedToken = token("placeholder-api-access-token", timestamp: 100)
    let updated10 = account.updateAccessToken(refreshedToken, for: authorization)
    #expect(updated10)
    #expect(account.accessToken == refreshedToken)
    #expect(account.authorizationID == authorization)
    #expect(account.userName == "placeholder-user")
    let updated11 = account.updateAccessToken(nil, for: authorization)
    #expect(updated11)
    #expect(account.authorizationID == nil)
    #expect(account.refreshToken == nil)
    #expect(account.accessToken == nil)
    #expect(account.userName == nil)
  }

  @Test func webSignOutRemovesAuthorizationButKeepsNameAndCannotBeUndoneByLateResult() throws {
    var account = webCredential()
    let authorization = try #require(account.authorizationID)
    account.accessToken = token("placeholder-access-token", timestamp: 100)
    let updated12 = account.updateWebAccessToken(
      nil, cookies: renewedCookies, renewedFrom: originalCookies, for: authorization,
    )
    #expect(updated12)
    #expect(account.authorizationID == nil)
    #expect(account.webSessionCookies == nil)
    #expect(account.accessToken == nil)
    #expect(account.signInMethod == .webSession)
    #expect(account.userName == "placeholder-user")
    let before = account
    let updated13 = account.updateWebAccessToken(
      token("placeholder-delayed-access-token", timestamp: 200), cookies: renewedCookies,
      renewedFrom: originalCookies, for: authorization,
    )
    #expect(!updated13)
    #expect(account == before)

    let decoded = try JSONDecoder().decode(RedditCredential.self, from: JSONEncoder().encode(account))
    #expect(decoded.authorizationID == nil)
    #expect(decoded.userName == "placeholder-user")
    // Signing in with the same cookie text still creates a distinct authorization.
    account.webSessionCookies = originalCookies
    #expect(try #require(account.authorizationID) != authorization)
  }

  @Test func explicitIdentityRemovalClearsWebNameAndRejectsLateResult() throws {
    var account = webCredential()
    let authorization = try #require(account.authorizationID)
    account.accessToken = token("placeholder-access-token", timestamp: 100)
    account.clearIdentity()
    #expect(account.authorizationID == nil)
    #expect(account.webSessionCookies == nil)
    #expect(account.accessToken == nil)
    #expect(account.userName == nil)
    let before = account
    let updated14 = account.updateWebAccessToken(
      token("placeholder-delayed-access-token", timestamp: 200), cookies: renewedCookies,
      renewedFrom: originalCookies, for: authorization,
    )
    #expect(!updated14)
    #expect(account == before)
  }
}
