//
//  RedditCredential.swift
//  Helio
//
//  Created by Igor Marcossi on 05/12/23.
//

import Alamofire
import Combine
import Defaults
import Foundation
import KeychainAccess
import SwiftUI

struct RedditCredential: Identifiable, Equatable, Hashable, Codable {
  static func defaultUserAgent(userName: String? = nil) -> String {
    "ios:com.sertacozercan.helio:v1.6.0 (by /u/\(userName ?? "UnknownUser"))"
  }

  enum CodingKeys: String, CodingKey { case id, apiAppID, apiAppSecret, accessToken, refreshToken, userName, profilePicture, _userAgent, signInMethod, webSessionCookies }

  /// How the credential gets its access tokens: from the user's own API key (`apiAppID`,
  /// `refreshToken`), or from a Reddit web session signed in with `RedditWebLoginView`.
  enum SignInMethod: String, Codable { case apiKey, webSession }

  var id: UUID
  var signInMethod: SignInMethod = .apiKey
  /// The reddit.com cookies of a web session, as a `Cookie` header. `nil` once Reddit signs the
  /// session out, which leaves the credential waiting for the user to sign in again.
  var webSessionCookies: String? = nil
  var isWebSession: Bool {
    signInMethod == .webSession
  }

  /// The key access tokens are renewed with, or `nil` when the credential can't renew them.
  var renewalKey: String? {
    switch signInMethod {
    case .apiKey: apiAppID.isEmpty ? nil : refreshToken
    case .webSession: webSessionCookies
    }
  }

  var apiAppID: String {
    willSet {
      if apiAppID != newValue {
        clearIdentity()
      }
    }
  }

  var apiAppSecret: String {
    willSet {
      if apiAppSecret != newValue {
        clearIdentity()
      }
    }
  }

  var accessToken: AccessToken? = nil
  var refreshToken: String? = nil
  var userName: String? = nil
  var _userAgent: String? = nil
  var userAgent: String {
    get {
      _userAgent ?? RedditCredential.defaultUserAgent(userName: userName)
    }
    set {
      _userAgent = newValue
    }
  }

  var profilePicture: String? = nil
  func isInKeychain() -> Bool {
    RedditCredentialsManager.shared.credentials.contains { $0.id == self.id }
  }

  var validationStatus: CredentialValidationState {
    if isWebSession {
      return webSessionCookies == nil ? .valid : .authorized
    }

    var newRedditAPIPairState: CredentialValidationState = .empty

    // Installed-app credentials have only a client id (no secret), so validity keys off the
    // 22-char app id alone. Existing web-app creds (also a 22-char id) remain valid too.
    if self.apiAppID.count == 22 {
      newRedditAPIPairState = .valid
    } else if self.apiAppID.count > 10 {
      newRedditAPIPairState = .maybeValid
    } else if !self.apiAppID.isEmpty {
      newRedditAPIPairState = .invalid
    }

    guard self.refreshToken != nil else { return newRedditAPIPairState }
    return .authorized
  }

  init(apiAppID: String = "", apiAppSecret: String = "", accessToken: String? = nil, refreshToken: String? = nil, expiration: Int? = nil, lastRefresh: Date? = nil, userName: String? = nil, profilePicture: String? = nil) {
    self.id = UUID()
    self.apiAppID = apiAppID
    self.apiAppSecret = apiAppSecret
    if let accessToken, let expiration, let lastRefresh {
      let newAccessToken = AccessToken(token: accessToken, expiration: expiration, lastRefresh: lastRefresh)
      self.accessToken = newAccessToken
    }
    self.refreshToken = refreshToken
    self.userName = userName
    self.profilePicture = profilePicture
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    apiAppID = try values.decode(String.self, forKey: .apiAppID)
    apiAppSecret = try values.decode(String.self, forKey: .apiAppSecret)
    accessToken = try values.decodeIfPresent(AccessToken.self, forKey: .accessToken)
    refreshToken = try values.decodeIfPresent(String.self, forKey: .refreshToken)
    userName = try values.decodeIfPresent(String.self, forKey: .userName)
    profilePicture = try values.decodeIfPresent(String.self, forKey: .profilePicture)
    _userAgent = try values.decodeIfPresent(String.self, forKey: ._userAgent)
    signInMethod = try values.decodeIfPresent(SignInMethod.self, forKey: .signInMethod) ?? .apiKey
    webSessionCookies = try values.decodeIfPresent(String.self, forKey: .webSessionCookies)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    try container.encode(id, forKey: .id)
    try container.encode(apiAppID, forKey: .apiAppID)
    try container.encode(apiAppSecret, forKey: .apiAppSecret)
    try container.encodeIfPresent(accessToken, forKey: .accessToken)
    try container.encodeIfPresent(refreshToken, forKey: .refreshToken)
    try container.encodeIfPresent(userName, forKey: .userName)
    try container.encodeIfPresent(profilePicture, forKey: .profilePicture)
    try container.encodeIfPresent(_userAgent, forKey: ._userAgent)
    try container.encode(signInMethod, forKey: .signInMethod)
    try container.encodeIfPresent(webSessionCookies, forKey: .webSessionCookies)
  }

  mutating func clearIdentity() {
    accessToken = nil
    refreshToken = nil
    userName = nil
    profilePicture = nil
    _userAgent = nil
    signInMethod = .apiKey
    webSessionCookies = nil
  }

  /// Fills the account name and avatar from `/api/v1/me`.
  mutating func setProfile(from me: UserData) {
    userName = me.name
    if let avatar = me.subreddit?.icon_img ?? me.icon_img ?? me.snoovatar_img, let rootAvatar = rootURL(avatar)?.absoluteString {
      profilePicture = rootAvatar
    }
  }

  func save(_ forceCreate: Bool = true) {
    RedditCredentialsManager.shared.saveCred(self, forceCreate: forceCreate)
  }

  func delete() {
    RedditCredentialsManager.shared.deleteCred(self)
  }

  /// `rejectedToken`: a token the request was refused with (401), which is never reused. A forced
  /// renewal reuses a fresh token only when it knows the rejected one, so the fresh one is newer.
  func getUpToDateToken(forceRenew: Bool = false, saveToken: Bool = true, rejectedToken: String? = nil) async -> AccessToken? {
    guard let renewalKey else { return nil }
    if let accessToken = self.accessToken, accessToken.isFresh, accessToken.token != rejectedToken, !forceRenew || rejectedToken != nil {
      return accessToken
    }
    return await AccessTokenRefresher.shared.token(refreshToken: renewalKey, forceRenew: forceRenew, rejected: rejectedToken) {
      if isWebSession {
        await mintWebSessionToken(cookies: renewalKey)
      } else {
        await fetchNewToken(refreshToken: renewalKey)
      }
    }

    func mintWebSessionToken(cookies: String) async -> AccessToken? {
      switch await RedditWebSession.mintToken(cookies: cookies, userAgent: userAgent) {
      case let .token(newAccessToken, renewedCookies):
        if saveToken {
          await updateSession(renewedFrom: cookies) { current in
            current.accessToken = newAccessToken
            current.webSessionCookies = renewedCookies
          }
        }
        return newAccessToken
      case .signedOut:
        // Keeps the account name, so the credential shows whom to sign in as again.
        if saveToken {
          await updateSession(renewedFrom: cookies) { current in
            current.webSessionCookies = nil
            current.accessToken = nil
          }
        }
        return nil
      case .failed:
        return nil
      }
    }

    // Changes the saved credential, not this copy, and only while it still has the session the
    // token came from: a sign-in that finished meanwhile wins.
    func updateSession(renewedFrom cookies: String, _ change: @escaping (inout RedditCredential) -> Void) async {
      await MainActor.run {
        guard var current = RedditCredentialsManager.getById(id), current.webSessionCookies == cookies else { return }
        change(&current)
        RedditCredentialsManager.shared.saveCred(current, forceCreate: false)
      }
    }

    func fetchNewToken(refreshToken: String) async -> AccessToken? {
      let payload = RedditAPI.RefreshAccessTokenPayload(refresh_token: refreshToken)
      let result = await RedditAPI.shared._doRequest(authenticated: false) { headers in
        await AF.request(
          "\(RedditAPI.redditWWWApiURLBase)/api/v1/access_token",
          method: .post,
          parameters: payload,
          encoder: URLEncodedFormParameterEncoder(destination: .httpBody),
          headers: headers,
        )
        .authenticate(username: apiAppID, password: apiAppSecret, persistence: .none)
        .validate()
        .serializingDecodable(RedditAPI.RefreshAccessTokenResponse.self).response.result
      }

      switch result {
      case let .success(data):
        let newAccessToken = RedditCredential.AccessToken(token: data.access_token, expiration: data.expires_in, lastRefresh: Date())
        if saveToken {
          var newSelf = self
          newSelf.accessToken = newAccessToken
          RedditCredentialsManager.shared.saveCred(newSelf, forceCreate: false)
        }
        return newAccessToken
      case let .failure(error):
        print("pipo", error, payload)
        switch error.responseCode {
        case 401:
          var selfCopy = self
          selfCopy.refreshToken = nil
          selfCopy.accessToken = nil
          selfCopy.userName = nil
          selfCopy.profilePicture = nil
          selfCopy.save(false)
        default:
          break
        }
        return nil
      }
    }
  }

  struct AccessToken: Equatable, Hashable, Codable {
    let token: String
    let expiration: Int
    let lastRefresh: Date

    /// Still usable, with a 100 s margin for requests in flight.
    var isFresh: Bool {
      Date().timeIntervalSince(lastRefresh) < Double(max(0, expiration - 100))
    }
  }

  enum CredentialValidationState: String {
    case authorized, valid, invalid, maybeValid, empty

    func getMeta() -> Meta {
      switch self {
      case .authorized: .init(color: .green, lottieIcon: "thumbup", label: "Perfect", description: "This means you can use this account normally.")
      case .maybeValid, .valid: .init(color: .orange, lottieIcon: "warning-appear", label: "Unauthorized", description: "This means you need to allow your credentials to access your account.")
      case .empty, .invalid: .init(color: .red, lottieIcon: "thumbdown", label: "Invalid", description: "This means that you credential info is wrong.")
      }
    }

    struct Meta: Equatable {
      let color: Color
      let lottieIcon: String
      let label: String
      let description: String
    }
  }
}
