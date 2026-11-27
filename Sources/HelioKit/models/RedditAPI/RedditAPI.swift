import Alamofire
import AuthenticationServices
import Combine
import Defaults
import Foundation
import KeychainAccess
import os
import SwiftUI

@Observable
class RedditAPI {
  static let shared = RedditAPI()
  static let redditApiURLBase = "https://oauth.reddit.com"
  static let redditWWWApiURLBase = "https://www.reddit.com"
  static let appURLScheme = "helioapp"
  static let appRedirectURI: String = "https://sozercan.github.io/helio/auth-success"

  private let currentAccount: @Sendable () async -> RedditCredential?
  private let session: Session

  init(session: Session = AF, currentAccount: @escaping @Sendable () async -> RedditCredential? = {
    await MainActor.run { RedditCredentialsManager.shared.selectedCredential }
  }) {
    self.session = session
    self.currentAccount = currentAccount
  }

  func captureAccount() async -> RedditCredential? {
    await currentAccount()
  }

  enum WebSessionAuth {
    case bearer
    case cookie(host: String? = nil)
  }

  func fetchRequestHeaders(
    force: Bool = false,
    includeAuth: Bool = true,
    altCredential: RedditCredential? = nil,
    saveToken: Bool = true,
    rejectedToken: String? = nil,
    webSessionAuth: WebSessionAuth = .bearer,
    requestURL: String? = nil,
  ) async -> HTTPHeaders? {
    var headers: HTTPHeaders = [
      "User-Agent": RedditCredential.defaultUserAgent(),
    ]
    if includeAuth {
      var credential = altCredential
      if credential == nil {
        credential = await currentAccount()
      }
      guard let selectedCredential = credential else { return nil }
      if selectedCredential.isWebSession, case .cookie = webSessionAuth {
        guard let session = await currentWebSession(for: selectedCredential) else { return nil }
        headers["Cookie"] = session.cookies
        headers["Referer"] = Self.originReferer(for: requestURL)
        headers["User-Agent"] = session.userAgent
      } else if let accessToken = await selectedCredential.getUpToDateToken(forceRenew: force, saveToken: saveToken, rejectedToken: rejectedToken) {
        headers["Authorization"] = "Bearer \(accessToken.token)"
        headers["User-Agent"] = selectedCredential.userAgent
      } else {
        return nil
      }
    }

    HTTPCookieStorage.shared.cookies?.forEach(HTTPCookieStorage.shared.deleteCookie)

    return headers
  }

  private func currentWebSession(for credential: RedditCredential) async -> (cookies: String, userAgent: String)? {
    guard let authorization = credential.authorizationID else { return nil }
    let installed = await MainActor.run { RedditCredentialsManager.getById(credential.id) }
    let current = if let installed, installed.authorizationID == authorization {
      installed
    } else {
      credential
    }
    guard let cookies = current.webSessionCookies, !cookies.isEmpty else { return nil }
    return (cookies, current.userAgent)
  }

  static func resolveURL(_ url: String, for credential: RedditCredential?, webSessionAuth: WebSessionAuth) -> String {
    guard
      let credential,
      credential.isWebSession,
      case let .cookie(host?) = webSessionAuth,
      var components = URLComponents(string: url)
    else { return url }
    components.host = host
    return components.string ?? url
  }

  static func originReferer(for url: String?) -> String {
    guard
      let url,
      let components = URLComponents(string: url),
      let scheme = components.scheme,
      let host = components.host
    else { return "\(redditWWWApiURLBase)/" }
    return "\(scheme)://\(host)/"
  }

  @MainActor
  static func accountID(_ altCredential: RedditCredential? = nil) -> UUID? {
    (altCredential ?? RedditCredentialsManager.shared.selectedCredential)?.id
  }

  @MainActor
  static func accountAuthorization(_ altCredential: RedditCredential? = nil) -> RedditCredential.AuthorizationID? {
    (altCredential ?? RedditCredentialsManager.shared.selectedCredential)?.authorizationID
  }

  private let reqModifier: Session.RequestModifier = { urlReq in
    urlReq.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    urlReq.httpShouldHandleCookies = false
  }

  func doRequest<D: Decodable>(
    _ url: String,
    authenticated: Bool = true,
    method: HTTPMethod,
    params: (some Encodable)? = nil,
    paramsLocation: URLEncodedFormParameterEncoder.Destination = .httpBody,
    decodable: D.Type,
    altCredential: RedditCredential? = nil,
    attempt: Int = 0,
    saveToken: Bool = true,
    webSessionAuth: WebSessionAuth = .bearer,
  ) async -> Result<D, AFError> {
    var credential = altCredential
    if authenticated, credential == nil {
      credential = await currentAccount()
    }
    guard !authenticated || credential != nil else { return .failure(.serverTrustEvaluationFailed(reason: .noPublicKeysFound)) }
    let account = credential?.id
    let authorization = credential?.authorizationID
    let resolvedURL = Self.resolveURL(url, for: credential, webSessionAuth: webSessionAuth)
    return await self._doRequest(authenticated: authenticated, altCredential: credential, saveToken: saveToken, webSessionAuth: webSessionAuth, requestURL: resolvedURL) { headers in
      let req = session.request(resolvedURL, method: method, parameters: params, encoder: URLEncodedFormParameterEncoder(destination: paramsLocation), headers: headers, requestModifier: reqModifier).validate()
      return await RedditRateLimit.shared.recording(req.serializingDecodable(decodable).response, account: account, authorization: authorization)
    }
  }

  func doRequest<D: Decodable>(
    _ url: String,
    authenticated: Bool = true,
    method: HTTPMethod,
    decodable: D.Type,
    altCredential: RedditCredential? = nil,
    attempt: Int = 0,
    saveToken: Bool = true,
    webSessionAuth: WebSessionAuth = .bearer,
  ) async -> Result<D, AFError> {
    var credential = altCredential
    if authenticated, credential == nil {
      credential = await currentAccount()
    }
    guard !authenticated || credential != nil else { return .failure(.serverTrustEvaluationFailed(reason: .noPublicKeysFound)) }
    let account = credential?.id
    let authorization = credential?.authorizationID
    let resolvedURL = Self.resolveURL(url, for: credential, webSessionAuth: webSessionAuth)
    return await self._doRequest(authenticated: authenticated, altCredential: credential, saveToken: saveToken, webSessionAuth: webSessionAuth, requestURL: resolvedURL) { headers in
      let req = session.request(resolvedURL, method: method, parameters: ["raw_json": 1], headers: headers, requestModifier: reqModifier).validate()
      return await RedditRateLimit.shared.recording(req.serializingDecodable(decodable).response, account: account, authorization: authorization)
    }
  }

  func doRequest(
    _ url: String,
    authenticated: Bool = true,
    method: HTTPMethod,
    params: some Encodable,
    paramsLocation: URLEncodedFormParameterEncoder.Destination = .httpBody,
    altCredential: RedditCredential? = nil,
    attempt: Int = 0,
    saveToken: Bool = true,
    webSessionAuth: WebSessionAuth = .bearer,
  ) async -> Result<String, AFError> {
    var credential = altCredential
    if authenticated, credential == nil {
      credential = await currentAccount()
    }
    guard !authenticated || credential != nil else { return .failure(.serverTrustEvaluationFailed(reason: .noPublicKeysFound)) }
    let account = credential?.id
    let authorization = credential?.authorizationID
    let resolvedURL = Self.resolveURL(url, for: credential, webSessionAuth: webSessionAuth)
    return await self._doRequest(authenticated: authenticated, altCredential: credential, saveToken: saveToken, webSessionAuth: webSessionAuth, requestURL: resolvedURL) { headers in
      let req = session.request(resolvedURL, method: method, parameters: params, encoder: URLEncodedFormParameterEncoder(destination: paramsLocation), headers: headers, requestModifier: reqModifier).validate()
      return await RedditRateLimit.shared.recording(req.serializingString().response, account: account, authorization: authorization)
    }
  }

  func _doRequest<D: Decodable>(
    attempt: Int = 0,
    forceAuth: Bool = false,
    authenticated: Bool = true,
    altCredential: RedditCredential? = nil,
    saveToken: Bool = true,
    rejectedToken: String? = nil,
    renewedToken: Bool = false,
    webSessionAuth: WebSessionAuth = .bearer,
    requestURL: String? = nil,
    req: (HTTPHeaders) async -> Result<D, AFError>,
  ) async -> Result<D, AFError> {
    guard !Task.isCancelled else { return .failure(.explicitlyCancelled) }
    var credential = altCredential
    if authenticated, credential == nil {
      credential = await currentAccount()
    }
    guard !Task.isCancelled else { return .failure(.explicitlyCancelled) }
    if authenticated, RedditRateLimit.shared.limitedUntil(account: credential?.id, authorization: credential?.authorizationID) != nil {
      return .failure(RedditRateLimit.limitedError)
    }
    guard
      !authenticated || credential != nil,
      let headers = await fetchRequestHeaders(force: forceAuth, includeAuth: authenticated, altCredential: credential, saveToken: saveToken, rejectedToken: rejectedToken, webSessionAuth: webSessionAuth, requestURL: requestURL)
    else { return .failure(.serverTrustEvaluationFailed(reason: .noPublicKeysFound)) }
    guard !Task.isCancelled else { return .failure(.explicitlyCancelled) }

    let result = await req(headers)
    guard case let .failure(error) = result, !Task.isCancelled else { return result }
    if authenticated, !renewedToken, error.responseCode == 401, let auth = headers["Authorization"] {
      let rejected = String(auth.dropFirst("Bearer ".count))
      return await self._doRequest(attempt: attempt, forceAuth: true, authenticated: authenticated, altCredential: credential, saveToken: saveToken,
                                   rejectedToken: rejected, renewedToken: true, webSessionAuth: webSessionAuth, requestURL: requestURL, req: req)
    }
    if attempt < Self.maxRetries, Self.isTransient(error) {
      try? await Task.sleep(for: .milliseconds(300 * (attempt + 1)))
      return await self._doRequest(attempt: attempt + 1, authenticated: authenticated, altCredential: credential, saveToken: saveToken,
                                   rejectedToken: rejectedToken, renewedToken: renewedToken, webSessionAuth: webSessionAuth, requestURL: requestURL, req: req)
    }
    return result
  }

  static let maxRetries = 2

  static func isTransient(_ error: AFError) -> Bool {
    if let code = error.responseCode {
      return (500 ... 599).contains(code)
    }
    guard case let .sessionTaskFailed(underlying) = error, let urlError = underlying as? URLError else { return false }
    switch urlError.code {
    case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
      return true
    default:
      return false
    }
  }

  func injectFirstAccessTokenInto(_ credential: inout RedditCredential, authCode: String) async -> Bool {
    if !credential.apiAppID.isEmpty {
      let headers = await fetchRequestHeaders(includeAuth: false)
      var code = authCode
      if code.hasSuffix("#_") {
        code = "\(code.dropLast(2))"
      }
      let payload = GetAccessTokenPayload(code: code)
      let response = await AF.request(
        "\(RedditAPI.redditWWWApiURLBase)/api/v1/access_token",
        method: .post,
        parameters: payload,
        encoder: URLEncodedFormParameterEncoder(destination: .httpBody),
        headers: headers,
      )
      .authenticate(username: credential.apiAppID, password: credential.apiAppSecret, persistence: .none)
      .serializingDecodable(GetAccessTokenResponse.self).response
      switch response.result {
      case let .success(data):
        let newAcessToken = RedditCredential.AccessToken(token: data.access_token, expiration: data.expires_in, lastRefresh: Date())
        credential.refreshToken = data.refresh_token
        credential.accessToken = newAcessToken
        if let meData = await self.fetchMe(altCredential: credential, saveToken: false) {
          credential.userName = meData.name
          if let avatar = (meData.subreddit?.icon_img ?? meData.icon_img ?? meData.snoovatar_img), let rootAvatar = rootURL(avatar)?.absoluteString {
            credential.profilePicture = rootAvatar
          }
          return true
        }
        return true
      case let .failure(error):
        print(error)
        return false
      }
    }
    return false
  }

  enum AuthorizationResult { case code(String), cancelled, failed }

  @MainActor
  func authorize(appID: String, using session: WebAuthenticationSession) async -> AuthorizationResult {
    let state = UUID().uuidString
    do {
      let callbackURL = try await session.authenticate(
        using: getAuthorizationCodeURL(appID, state: state),
        callbackURLScheme: Self.appURLScheme,
        preferredBrowserSession: .shared,
      )
      guard let code = Self.authCode(from: callbackURL, state: state) else { return .failed }
      return .code(code)
    } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
      return .cancelled
    } catch {
      return .failed
    }
  }

  static func authCode(from url: URL, state: String) -> String? {
    guard
      url.scheme == appURLScheme,
      url.host == "auth-success",
      let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
      query.first(where: { $0.name == "state" })?.value == state,
      let code = query.first(where: { $0.name == "code" })?.value
    else { return nil }
    return code
  }

  func getAuthorizationCodeURL(_ appID: String, state: String) -> URL {
    let response_type = "code"
    let redirect_uri: String = RedditAPI.appRedirectURI
    let duration = "permanent"
    let scope = "identity,edit,flair,history,modconfig,modflair,modlog,modposts,modwiki,mysubreddits,privatemessages,read,report,save,submit,subscribe,vote,wikiedit,wikiread"

    return URL(string: "https://www.reddit.com/api/v1/authorize.compact?client_id=\(appID.trimmingCharacters(in: .whitespaces))&response_type=\(response_type)&state=\(state)&redirect_uri=\(redirect_uri)&duration=\(duration)&scope=\(scope)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)!
  }

  struct RefreshAccessTokenResponse: Decodable {
    let access_token: String
    let token_type: String
    let expires_in: Int
    let scope: String
  }

  struct GetAccessTokenResponse: Decodable {
    let access_token: String
    let token_type: String
    let refresh_token: String
    let scope: String
    let expires_in: Int
  }

  struct RefreshAccessTokenPayload: Encodable {
    let grant_type = "refresh_token"
    let refresh_token: String
  }

  struct GetAccessTokenPayload: Encodable {
    let grant_type = "authorization_code"
    let code: String
    let redirect_uri = RedditAPI.appRedirectURI
  }
}

struct ListingChild<T: Codable & Hashable>: Codable, Defaults.Serializable, Hashable {
  let kind: String?
  var data: T?
}

struct Listing<T: Codable & Hashable>: Codable, Defaults.Serializable, Hashable {
  let kind: String?
  var data: ListingData<T>?
}

struct ListingData<T: Codable & Hashable>: Codable, Defaults.Serializable, Hashable {
  let after: String?
  let dist: Int?
  let modhash: String?
  let geo_filter: String?
  var children: [ListingChild<T>]?
  var skippedChildren = 0

  private enum CodingKeys: String, CodingKey {
    case after, dist, modhash, geo_filter, children
  }
}

extension ListingData {
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    after = try container.decodeIfPresent(String.self, forKey: .after)
    dist = try container.decodeIfPresent(Int.self, forKey: .dist)
    modhash = try container.decodeIfPresent(String.self, forKey: .modhash)
    geo_filter = try container.decodeIfPresent(String.self, forKey: .geo_filter)
    guard let lossyChildren = try container.decodeIfPresent([LossyListingChild<T>].self, forKey: .children) else {
      children = nil
      return
    }
    let decoded = lossyChildren.compactMap(\.value)
    let errors = lossyChildren.compactMap(\.error)
    if decoded.isEmpty, let error = errors.first {
      throw error
    }
    for error in errors {
      listingLogger.error("Skipping a listing item that failed to decode: \(String(describing: error), privacy: .private)")
    }
    children = decoded
    skippedChildren = errors.count
  }
}

private let listingLogger = Logger(subsystem: "com.sertacozercan.helio", category: "Listing")

private struct LossyListingChild<T: Codable & Hashable>: Decodable {
  let value: ListingChild<T>?
  let error: Error?

  init(from decoder: Decoder) throws {
    do {
      value = try ListingChild<T>(from: decoder)
      error = nil
    } catch {
      value = nil
      self.error = error
    }
  }
}

enum Either<A: Codable & Hashable, B: Codable & Hashable>: Codable, Hashable {
  case first(A)
  case second(B)

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    do {
      let firstType = try container.decode(A.self)
      self = .first(firstType)
    } catch let firstError {
      do {
        let secondType = try container.decode(B.self)
        self = .second(secondType)
      } catch let secondError {
        let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Type mismatch for both types.", underlyingError: Swift.DecodingError.typeMismatch(Any.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "First type error: \(firstError). Second type error: \(secondError)")))
        throw DecodingError.dataCorrupted(context)
      }
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case let .first(value):
      try container.encode(value)
    case let .second(value):
      try container.encode(value)
    }
  }
}
