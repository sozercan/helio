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
  var controller: UIViewController? {
    didSet { updateContentPopGesture() }
  }

  private var swipeAnywhereEnabled = false
  private var isAtRoot = true

  init(routerID: String) {
    self.routerID = routerID
  }

  func setSwipeAnywhereEnabled(_ enabled: Bool) {
    swipeAnywhereEnabled = enabled
    updateContentPopGesture()
  }

  func setAtRoot(_ atRoot: Bool) {
    isAtRoot = atRoot
    updateContentPopGesture()
  }

  private func updateContentPopGesture() {
    controller?.navigationController?.interactiveContentPopGestureRecognizer?.isEnabled = swipeAnywhereEnabled && !isAtRoot
  }
}

@Observable
class Router: Hashable, Equatable, Identifiable {
  let id: String

  var firstSelected: NavDest? {
    get { fullPath.first }
    set {
      if let newValue {
        if let first = fullPath.first, first.isSameFeed(as: newValue) {
          first.takeSubredditDetails(from: newValue)
        } else {
          fullPath = [newValue]
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

  var fullPath: [NavDest] = [] {
    didSet {
      if fullPath.isEmpty != isAtRoot {
        isAtRoot = fullPath.isEmpty
      }
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

  private(set) var isAtRoot = true {
    didSet { navController.setAtRoot(isAtRoot) }
  }

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

  func navigateTo(_ dest: NavDest, _ reset: Bool = false, from column: Column? = nil) {
    if reset {
      path = [dest]
    } else if column == .feed, !fullPath.isEmpty {
      let feedStack = Array(fullPath[..<(postColumnStart ?? fullPath.count)])
      fullPath = feedStack + [dest] + (dest.opensInPostColumn ? [] : postColumn)
    } else {
      path.append(dest)
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
        }
      }

      case post(Post)
      case postHighlighted(Post, String)
      case subFeed(Subreddit)
      case subInfo(Subreddit)
      case multiFeed(Multi)
      case multiInfo(Multi)
      case user(User)
    }

    enum Setting: String, Hashable, Codable, Identifiable {
      var id: String {
        self.rawValue
      }

      case behavior, appearance, credentials, about, commentSwipe, postSwipe, faq, general, themes, filteredSubreddits, webExtensions
    }
  }

  func showFeedRoot(_ dest: NavDest) {
    if let first = fullPath.first, first.isSameFeed(as: dest) {
      first.takeSubredditDetails(from: dest)
      fullPath = [first]
    } else {
      fullPath = [dest]
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
