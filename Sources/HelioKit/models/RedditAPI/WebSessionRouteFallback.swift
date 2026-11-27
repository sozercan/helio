import Alamofire
import Foundation
import Synchronization

struct WebSessionRoute: Equatable, Hashable, Sendable {
  enum Auth: Equatable, Hashable, Sendable {
    case bearer
    case cookie
  }

  let host: String
  let auth: Auth
  let dotJSONSuffix: Bool

  init(host: String, auth: Auth, dotJSONSuffix: Bool = false) {
    self.host = host
    self.auth = auth
    self.dotJSONSuffix = dotJSONSuffix
  }

  static let oauthBearer = Self(host: "oauth.reddit.com", auth: .bearer)
  static let oauthCookie = Self(host: "oauth.reddit.com", auth: .cookie)
  static let wwwCookie = Self(host: "www.reddit.com", auth: .cookie)
  static let wwwDotJSONCookie = Self(host: "www.reddit.com", auth: .cookie, dotJSONSuffix: true)
  static let oldCookie = Self(host: "old.reddit.com", auth: .cookie)
  static let apiCookie = Self(host: "api.reddit.com", auth: .cookie)

  var webSessionAuth: RedditAPI.WebSessionAuth {
    switch auth {
    case .bearer:
      .bearer
    case .cookie:
      .cookie(host: host)
    }
  }

  func apply(to url: String) -> String {
    guard var components = URLComponents(string: url) else { return url }
    components.host = host
    if dotJSONSuffix {
      let path = components.path
      if path.hasSuffix(".json") {
        let base = String(path.dropLast(5))
        if !base.hasSuffix("/") {
          components.path = "\(base)/.json"
        }
      } else if !path.hasSuffix("/.json") {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        components.path = "\(trimmed)/.json"
      }
    }
    return components.string ?? url
  }
}

enum WebSessionRoutePlanner {
  static func isFallbackEligible(method: HTTPMethod, url: String) -> Bool {
    if method == .get {
      return true
    }
    if method == .post {
      return endpointKey(for: url) == "/api/morechildren"
    }
    return false
  }

  static func endpointKey(for url: String) -> String {
    let rawPath = URLComponents(string: url)?.path ?? url
    var path = rawPath.lowercased()
    while path.hasSuffix("/") {
      path.removeLast()
    }
    if path.hasSuffix(".json") {
      path.removeLast(5)
    }
    while path.hasSuffix("/") {
      path.removeLast()
    }
    while path.hasPrefix("/") {
      path.removeFirst()
    }
    return "/\(path)"
  }

  static func patternKey(for url: String) -> String {
    let key = endpointKey(for: url)
    let segments = key.split(separator: "/").map(String.init)
    guard !segments.isEmpty else { return "/" }
    if segments[0] == "api" {
      return key
    }
    if segments[0] == "r", segments.count >= 2 {
      let sub = segments[1]
      if sub == "all" || sub.hasPrefix("all-") || sub.hasPrefix("all+") {
        return segments.count == 2 ? "/r/all" : "/r/all/*"
      }
      if segments.count >= 3, segments[2] == "comments" {
        return "/r/*/comments/*"
      }
      if segments.count == 3, segments[2] == "search" {
        return sub.contains("+") ? "/r/+/search" : "/r/*/search"
      }
      if segments.count == 3, ["hot", "new", "rising"].contains(segments[2]) {
        return sub.contains("+") ? "/r/+/\(segments[2])" : "/r/*/\(segments[2])"
      }
      return sub.contains("+") ? "/r/+/*" : "/r/*/*"
    }
    if segments[0] == "comments" {
      return "/comments/*"
    }
    if segments.count == 1, ["hot", "new", "rising", "search"].contains(segments[0]) {
      return "/\(segments[0])"
    }
    if segments == ["subreddits", "search"] {
      return "/subreddits/search"
    }
    return key
  }

  static func primaryRoute(for defaultAuth: RedditAPI.WebSessionAuth) -> WebSessionRoute {
    switch defaultAuth {
    case .bearer:
      .oauthBearer
    case let .cookie(host):
      WebSessionRoute(host: host ?? "oauth.reddit.com", auth: .cookie)
    }
  }

  static func routes(for url: String, method: HTTPMethod, defaultAuth: RedditAPI.WebSessionAuth) -> [WebSessionRoute] {
    let primary = primaryRoute(for: defaultAuth)
    guard isFallbackEligible(method: method, url: url) else {
      return [primary]
    }
    let pattern = patternKey(for: url)
    let candidates: [WebSessionRoute] = switch pattern {
    case "/api/info", "/api/morechildren":
      [primary, .oauthCookie, .wwwDotJSONCookie, .oldCookie]
    case "/search", "/subreddits/search", "/r/*/search", "/r/+/search":
      [primary, .oauthCookie, .oldCookie]
    case "/r/all", "/r/all/*":
      [primary, .oauthCookie, .apiCookie, .oldCookie]
    case "/r/*/comments/*", "/comments/*":
      [primary, .wwwCookie, .oauthCookie, .oldCookie]
    case "/hot", "/new", "/rising", "/r/*/hot", "/r/*/new", "/r/*/rising", "/r/+/hot", "/r/+/new", "/r/+/rising":
      [primary, .oauthCookie, .wwwCookie]
    default:
      primary.auth == .bearer ? [primary, .oauthCookie] : [primary]
    }
    var deduplicated: [WebSessionRoute] = []
    for route in candidates where !deduplicated.contains(route) {
      deduplicated.append(route)
    }
    return deduplicated
  }
}

final class WebSessionRouteHealth: Sendable {
  static let shared = WebSessionRouteHealth()
  static let blockThreshold = 3
  static let baseCooldown: TimeInterval = 3600
  static let maxCooldown: TimeInterval = 8 * 3600

  private struct RouteKey: Hashable, Sendable {
    let account: UUID
    let authorization: RedditCredential.AuthorizationID?
    let pattern: String
    let route: WebSessionRoute
  }

  private struct Entry: Sendable {
    var consecutiveBlocks = 0
    var cooldownExponent = 0
    var cooledDownUntil: Date?
  }

  private let now: @Sendable () -> Date
  private let entries = Mutex<[RouteKey: Entry]>([:])

  init(now: @escaping @Sendable () -> Date = Date.init) {
    self.now = now
  }

  func orderedRoutes(
    _ routes: [WebSessionRoute],
    account: UUID?,
    authorization: RedditCredential.AuthorizationID? = nil,
    pattern: String,
  ) -> [WebSessionRoute] {
    guard let account, !routes.isEmpty else { return routes }
    let currentTime = now()
    return entries.withLock { store in
      routes.filter { route in
        guard let until = store[RouteKey(account: account, authorization: authorization, pattern: pattern, route: route)]?.cooledDownUntil else {
          return true
        }
        return until <= currentTime
      }
    }
  }

  func recordBlock(
    account: UUID?,
    authorization: RedditCredential.AuthorizationID? = nil,
    pattern: String,
    route: WebSessionRoute,
  ) {
    guard let account else { return }
    let currentTime = now()
    entries.withLock { store in
      let key = RouteKey(account: account, authorization: authorization, pattern: pattern, route: route)
      var entry = store[key] ?? Entry()
      entry.consecutiveBlocks += 1
      if entry.consecutiveBlocks >= Self.blockThreshold {
        let multiplier = pow(2.0, Double(entry.cooldownExponent))
        let duration = min(Self.baseCooldown * multiplier, Self.maxCooldown)
        entry.cooledDownUntil = currentTime.addingTimeInterval(duration)
        entry.consecutiveBlocks = 0
        entry.cooldownExponent = min(entry.cooldownExponent + 1, 3)
      }
      store[key] = entry
    }
  }

  func recordSuccess(
    account: UUID?,
    authorization: RedditCredential.AuthorizationID? = nil,
    pattern: String,
    route: WebSessionRoute,
  ) {
    guard let account else { return }
    entries.withLock { store in
      store.removeValue(forKey: RouteKey(account: account, authorization: authorization, pattern: pattern, route: route))
    }
  }

  func isCoolingDown(
    account: UUID,
    authorization: RedditCredential.AuthorizationID? = nil,
    pattern: String,
    route: WebSessionRoute,
  ) -> Bool {
    let currentTime = now()
    return entries.withLock { store in
      guard let until = store[RouteKey(account: account, authorization: authorization, pattern: pattern, route: route)]?.cooledDownUntil else {
        return false
      }
      return until > currentTime
    }
  }
}
