import Alamofire
import Combine
import CryptoKit
import Defaults
import Foundation
import KeychainAccess
import os
import SwiftUI

struct RedditCredential: Identifiable, Equatable, Hashable, Codable, Sendable {
  static func defaultUserAgent(userName: String? = nil) -> String {
    "ios:com.sertacozercan.helio:v1.6.0 (by /u/\(userName ?? "UnknownUser"))"
  }

  struct AuthorizationID: Hashable, Sendable {
    let credentialID: UUID
    let grantID: Data

    fileprivate init(_ credential: RedditCredential, refreshToken: String) {
      credentialID = credential.id
      var bytes = Data()
      for value in [credential.signInMethod.rawValue, credential.apiAppID, credential.apiAppSecret, refreshToken] {
        bytes.append(contentsOf: "\(value.utf8.count):".utf8)
        bytes.append(contentsOf: value.utf8)
      }
      grantID = Data(SHA256.hash(data: bytes))
    }
  }

  var authorizationID: AuthorizationID? {
    guard let renewalKey, !renewalKey.isEmpty else { return nil }
    return AuthorizationID(self, refreshToken: isWebSession ? webSessionID.uuidString : renewalKey)
  }

  @discardableResult
  mutating func updateAccessToken(_ token: AccessToken?, for authorization: AuthorizationID) -> Bool {
    guard !isWebSession, authorizationID == authorization else { return false }
    if let token {
      if let current = accessToken, current.lastRefresh > token.lastRefresh {
        return false
      }
      accessToken = token
    } else {
      clearIdentity()
    }
    return true
  }

  @discardableResult
  mutating func backfillUserName(_ name: String, for authorization: AuthorizationID) -> Bool {
    guard authorizationID == authorization, userName?.isEmpty ?? true, !name.isEmpty else { return false }
    userName = name
    return true
  }

  @discardableResult
  mutating func updateWebAccessToken(_ token: AccessToken?, cookies: String?, renewedFrom: String, for authorization: AuthorizationID) -> Bool {
    guard isWebSession, authorizationID == authorization, webSessionCookies == renewedFrom else { return false }
    if let token, let current = accessToken, current.lastRefresh > token.lastRefresh {
      return false
    }
    let sessionID = webSessionID
    accessToken = token
    webSessionCookies = token == nil ? nil : cookies
    webSessionID = sessionID
    return true
  }

  enum CodingKeys: String, CodingKey { case id, apiAppID, apiAppSecret, accessToken, refreshToken, userName, profilePicture, _userAgent, signInMethod, webSessionCookies, webSessionID }

  enum SignInMethod: String, Codable, Sendable { case apiKey, webSession }

  var id: UUID
  var signInMethod: SignInMethod = .apiKey
  var webSessionID = UUID()
  var webSessionCookies: String? = nil {
    willSet {
      if webSessionCookies != newValue {
        webSessionID = UUID()
      }
    }
  }

  var isWebSession: Bool {
    signInMethod == .webSession
  }

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
  @MainActor
  func isInKeychain() -> Bool {
    RedditCredentialsManager.shared.credentials.contains { $0.id == self.id }
  }

  var validationStatus: CredentialValidationState {
    if isWebSession {
      return webSessionCookies == nil ? .valid : .authorized
    }

    var newRedditAPIPairState: CredentialValidationState = .empty

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
    webSessionID = try values.decodeIfPresent(UUID.self, forKey: .webSessionID) ?? id
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
    try container.encode(webSessionID, forKey: .webSessionID)
  }

  mutating func clearIdentity() {
    accessToken = nil
    refreshToken = nil
    userName = nil
    profilePicture = nil
    _userAgent = nil
    signInMethod = .apiKey
    webSessionCookies = nil
    webSessionID = UUID()
  }

  mutating func setProfile(from me: UserData) {
    userName = me.name
    if let avatar = me.subreddit?.icon_img ?? me.icon_img ?? me.snoovatar_img, let rootAvatar = rootURL(avatar)?.absoluteString {
      profilePicture = rootAvatar
    }
  }

  @MainActor
  func save(_ forceCreate: Bool = true) {
    RedditCredentialsManager.shared.saveCred(self, forceCreate: forceCreate)
  }

  private func reusableAccessToken(forceRenew: Bool, rejectedToken: String?) -> AccessToken? {
    guard
      let accessToken,
      accessToken.isFresh,
      accessToken.token != rejectedToken,
      !forceRenew || rejectedToken != nil,
      !isWebSession || RedditWebSession.isCurrentClientToken(accessToken.token)
    else { return nil }
    return accessToken
  }

  func getUpToDateToken(forceRenew: Bool = false, saveToken: Bool = true, rejectedToken: String? = nil) async -> AccessToken? {
    guard let authorization = authorizationID else { return nil }
    let installed = await MainActor.run { RedditCredentialsManager.getById(id) }
    let current = if let installed, installed.authorizationID == authorization {
      installed
    } else {
      self
    }
    guard let refreshToken = current.renewalKey else { return nil }
    if let accessToken = current.reusableAccessToken(forceRenew: forceRenew, rejectedToken: rejectedToken) {
      return accessToken
    }
    let outcome = await AccessTokenRefresher.shared.refresh(for: authorization, forceRenew: forceRenew, rejected: rejectedToken) {
      if current.isWebSession {
        switch await RedditWebSession.mintToken(cookies: refreshToken, userAgent: current.userAgent) {
        case let .token(token, cookies): return .webSessionToken(token, cookies: cookies)
        case .signedOut: return .rejected
        case .failed: return .failed
        }
      }
      return await fetchNewToken()
    }
    if saveToken {
      switch outcome {
      case let .token(token): await RedditCredentialsManager.shared.updateAccessToken(token, for: authorization)
      case let .webSessionToken(token, cookies):
        await RedditCredentialsManager.shared.updateWebAccessToken(token, cookies: cookies, renewedFrom: refreshToken, for: authorization)
      case .rejected:
        await MainActor.run {
          guard let saved = RedditCredentialsManager.getById(id),
                saved.authorizationID == authorization, saved.accessToken == current.accessToken
          else { return }
          if current.isWebSession {
            RedditCredentialsManager.shared.updateWebAccessToken(nil, cookies: nil, renewedFrom: refreshToken, for: authorization)
          } else {
            RedditCredentialsManager.shared.updateAccessToken(nil, for: authorization)
          }
        }
      case .failed: break
      }
    }
    return outcome.accessToken

    func fetchNewToken() async -> AccessTokenRefresher.Outcome {
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
        return .token(newAccessToken)
      case let .failure(error):
        Logger(subsystem: "com.sertacozercan.helio", category: "Authentication")
          .error("Access-token refresh failed (status \(error.responseCode ?? 0))")
        return error.responseCode == 401 ? .rejected : .failed
      }
    }
  }

  struct AccessToken: Equatable, Hashable, Codable, Sendable {
    let token: String
    let expiration: Int
    let lastRefresh: Date

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
