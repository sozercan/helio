import Foundation
import SwiftUI

class ViewControllerHolder: Identifiable, Equatable {
  static func == (lhs: ViewControllerHolder, rhs: ViewControllerHolder) -> Bool {
    lhs.id == rhs.id
  }

  var id: String {
    "ctrl-holder-\(self.routerID)"
  }

  let routerID: String
  private var navigationControllers = NSHashTable<UINavigationController>.weakObjects()
  private var swipeAnywhereEnabled = false

  init(routerID: String) {
    self.routerID = routerID
  }

  func attach(_ controller: UIViewController) {
    for nav in Self.ancestorNavigationControllers(of: controller) {
      navigationControllers.add(nav)
      updateContentPopGesture(on: nav)
    }
  }

  private static func ancestorNavigationControllers(of controller: UIViewController) -> [UINavigationController] {
    var result: [UINavigationController] = []
    var current: UIViewController? = controller
    while let candidate = current {
      if let nav = candidate as? UINavigationController {
        result.append(nav)
      }
      if let nav = candidate.navigationController, !result.contains(where: { $0 === nav }) {
        result.append(nav)
      }
      current = candidate.parent
    }
    return result
  }

  func setSwipeAnywhereEnabled(_ enabled: Bool) {
    swipeAnywhereEnabled = enabled
    updateContentPopGestures()
  }

  func updateContentPopGestures() {
    for nav in navigationControllers.allObjects {
      updateContentPopGesture(on: nav)
    }
  }

  func scheduleContentPopGestureUpdate() {
    updateContentPopGestures()
    Task { @MainActor [weak self] in
      self?.updateContentPopGestures()
    }
  }

  private func updateContentPopGesture(on nav: UINavigationController) {
    nav.interactiveContentPopGestureRecognizer?.isEnabled = swipeAnywhereEnabled && nav.viewControllers.count > 1
  }
}

@Observable
class Router: Hashable, Equatable, Identifiable {
  let id: String

  var firstSelected: NavDest? {
    get { fullPath.first }
    set {
      if let newValue {
        let explicitFeed = ReadingSessionStore.feedIdentifier(for: newValue)
        if let first = fullPath.first, first.isSameFeed(as: newValue) {
          first.takeSubredditDetails(from: newValue)
          if let explicitFeed {
            onFeedVisit?(explicitFeed, true)
          }
        } else {
          setPath(reportingExplicitFeed: explicitFeed) {
            fullPath = [newValue]
          }
        }
      } else {
        fullPath = []
      }
    }
  }

  var firstIsSidebarSelection = false

  var showsPostBesideFeed = false

  var canGoBack: Bool {
    let protectsRoot = firstIsSidebarSelection && fullPath.first?.isFeed == true
    return fullPath.count > (protectsRoot ? 1 : 0)
  }

  @ObservationIgnored var onFeedVisit: ((String, Bool) -> Void)?
  @ObservationIgnored var onFeedCleared: (() -> Void)?

  var fullPath: [NavDest] = [] {
    didSet {
      if fullPath.isEmpty != isAtRoot {
        isAtRoot = fullPath.isEmpty
      }
      navController.scheduleContentPopGestureUpdate()
      guard !suppressNextFeedVisitNotification else { return }
      if let feedName = ReadingSessionStore.latestFeedName(in: fullPath) {
        onFeedVisit?(feedName, false)
      } else {
        onFeedCleared?()
      }
    }
  }

  @ObservationIgnored private var suppressNextFeedVisitNotification = false

  private func setPath(reportingExplicitFeed explicitFeed: String?, _ update: () -> Void) {
    suppressNextFeedVisitNotification = explicitFeed != nil
    update()
    suppressNextFeedVisitNotification = false
    if let explicitFeed {
      onFeedVisit?(explicitFeed, true)
    }
  }

  var path: [NavDest] {
    get { Array(self.fullPath.dropFirst()) }
    set {
      if fullPath.isEmpty {
        self.fullPath = newValue
      } else {
        self.fullPath = [fullPath[0]] + newValue
      }
    }
  }

  private(set) var isAtRoot = true

  var navController: ViewControllerHolder

  init(id: String) {
    self.id = id
    self.navController = ViewControllerHolder(routerID: id)
  }

  func goBack() {
    if canGoBack {
      _ = withAnimation { self.fullPath.removeLast() }
    }
  }

  func resetNavPath() {
    withAnimation { self.fullPath.removeAll() }
  }

  func openAdjacentPost(_ dest: NavDest) {
    guard !fullPath.isEmpty else {
      navigateTo(dest)
      return
    }
    let feedStack = Array(fullPath[..<(postColumnStart ?? fullPath.count)])
    fullPath = feedStack + [dest]
  }

  func navigateTo(_ dest: NavDest, _ reset: Bool = false, from column: Column? = nil) {
    let explicitFeed = ReadingSessionStore.feedIdentifier(for: dest)
    setPath(reportingExplicitFeed: explicitFeed) {
      if reset {
        path = [dest]
      } else if column == .feed, showsPostBesideFeed, !fullPath.isEmpty {
        let feedStack = Array(fullPath[..<(postColumnStart ?? fullPath.count)])
        fullPath = feedStack + [dest] + (dest.opensInPostColumn ? [] : postColumn)
      } else {
        path.append(dest)
      }
    }
  }

  enum Column {
    case feed, post
  }

  var postColumnStart: Int? {
    fullPath.indices.dropFirst().first { fullPath[$0].opensInPostColumn }
  }

  var postColumn: [NavDest] {
    postColumnStart.map { Array(fullPath[$0...]) } ?? []
  }

  func column(for dest: NavDest) -> Column {
    if let start = postColumnStart, let index = fullPath.lastIndex(of: dest), index >= start {
      return .post
    }
    return .feed
  }

  var feedPath: [NavDest] {
    get { Array(fullPath.dropFirst().prefix(max(0, (postColumnStart ?? fullPath.count) - 1))) }
    set {
      guard let feed = fullPath.first else { return }
      fullPath = [feed] + newValue + postColumn
    }
  }

  var postPath: [NavDest] {
    get { Array(postColumn.dropFirst()) }
    set {
      guard let start = postColumnStart else { return }
      fullPath = Array(fullPath[...start]) + newValue
    }
  }

  var feedPanePath: [NavDest] {
    get { Array(fullPath.prefix(postColumnStart ?? fullPath.count)) }
    set { fullPath = newValue.isEmpty ? [] : newValue + postColumn }
  }

  func closePost() {
    if let start = postColumnStart {
      fullPath = Array(fullPath[..<start])
    }
  }

  enum NavDest: Hashable, Codable, Identifiable {
    var id: String {
      switch self {
      case let .reddit(reddit): reddit.id
      case let .setting(setting): setting.id
      case let .web(url): "web-\(url.absoluteString)"
      }
    }

    case reddit(Reddit)
    case setting(Setting)
    case web(URL)

    var opensInPostColumn: Bool {
      switch self {
      case .reddit(.post), .reddit(.postHighlighted), .web: true
      default: false
      }
    }

    enum Reddit: Hashable, Codable, Identifiable {
      var id: String {
        switch self {
        case let .post(post): post.id
        case let .postHighlighted(post, _): post.id
        case let .subFeed(subreddit): subreddit.id
        case let .subInfo(subreddit): subreddit.id
        case let .multiFeed(multi): multi.id
        case let .multiInfo(multi): multi.id
        case let .user(user): user.id
        case .friends: "friends"
        }
      }

      case post(Post)
      case postHighlighted(Post, String)
      case subFeed(Subreddit)
      case subInfo(Subreddit)
      case multiFeed(Multi)
      case multiInfo(Multi)
      case user(User)
      case friends
    }

    enum Setting: String, Hashable, Codable, Identifiable {
      var id: String {
        self.rawValue
      }

      case behavior, appearance, credentials, about, commentSwipe, postSwipe, faq, general, themes, filteredSubreddits, webExtensions
    }
  }

  func showFeedRoot(_ dest: NavDest) {
    let explicitFeed = ReadingSessionStore.feedIdentifier(for: dest)
    setPath(reportingExplicitFeed: explicitFeed) {
      if let first = fullPath.first, first.isSameFeed(as: dest) {
        first.takeSubredditDetails(from: dest)
        fullPath = [first]
      } else {
        fullPath = [dest]
      }
    }
  }

  enum CodingKeys: String, CodingKey {
    case id, firstSelected, path
  }

  static func == (lhs: Router, rhs: Router) -> Bool {
    lhs.id == rhs.id
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
    hasher.combine(firstSelected)
    hasher.combine(path)
  }
}

extension Router.NavDest {
  var subredditFeedName: String? {
    guard case let .reddit(.subFeed(sub)) = self else { return nil }
    if sub.data == nil, builtInFeedIDs.contains(sub.id) {
      return "feed:\(sub.id)"
    }
    return sub.rawSubredditName.lowercased()
  }

  var isFeed: Bool {
    switch self {
    case .reddit(.subFeed), .reddit(.multiFeed): true
    default: false
    }
  }

  var carriesSubredditData: Bool {
    if case let .reddit(.subFeed(sub)) = self {
      return sub.data != nil
    }
    return false
  }

  func takeSubredditDetails(from other: Router.NavDest) {
    guard case let .reddit(.subFeed(sub)) = self, case let .reddit(.subFeed(otherSub)) = other,
          sub !== otherSub, let data = otherSub.data else { return }
    sub.data = sub.data.map { $0.takingAccountState(from: data) } ?? data
  }

  func isSameFeed(as other: Router.NavDest) -> Bool {
    if let name = subredditFeedName, let otherName = other.subredditFeedName {
      return name == otherName
    }
    return self == other
  }
}

let builtInFeedIDs: Set<String> = ["home", "popular", "all", savedKeyword]
