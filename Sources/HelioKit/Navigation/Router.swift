//
//  Router.swift
//  Helio
//
//  Created by Igor Marcossi on 05/08/23.
//

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

  /// "Navigation everywhere" setting. Off by default because the full-width pop gesture
  /// competes with the horizontal post/comment swipe actions, which are disabled while it's on.
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

  /// iOS 26's built-in full-width back swipe. The edge swipe (`interactivePopGestureRecognizer`)
  /// is left untouched.
  private func updateContentPopGesture() {
    controller?.navigationController?.interactiveContentPopGestureRecognizer?.isEnabled = swipeAnywhereEnabled && !isAtRoot
  }
}

@Observable
class Router: Hashable, Equatable, Identifiable {
  let id: String

  /// The posts tab's sidebar selection: the feed at the root of the detail column. Choosing a
  /// different one replaces the whole detail path, so screens opened from the previous feed don't
  /// stay stacked on the new one.
  var firstSelected: NavDest? {
    get { fullPath.first }
    set {
      if let newValue {
        if let first = fullPath.first, first.isSameFeed(as: newValue) {
          // The same feed keeps its screens, and takes the subreddit's details when they come
          // along (opened from a link by name, then chosen in the sidebar; or fresher ones).
          first.takeSubredditDetails(from: newValue)
        } else {
          fullPath = [newValue]
        }
      } else {
        fullPath = []
      }
    }
  }

  /// True while the posts split view shows the sidebar beside the detail column. Then the path's
  /// first element is the sidebar's selection, not a screen Back can leave: removing it would
  /// blank the detail column. When the split view collapses into one stack, it pops like any
  /// other screen and Back returns to the subs list.
  var firstIsSidebarSelection = false

  /// Back can't remove the sidebar's feed beside the detail column, but a post or a user opened
  /// as the first screen (from a link) can always be closed.
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

  func navigateTo(_ dest: NavDest, _ reset: Bool = false) {
    self.path = reset ? [dest] : self.path + [dest]
  }

  enum NavDest: Hashable, Codable, Identifiable {
    var id: String {
      switch self {
      case let .reddit(reddit): reddit.id
      case let .setting(setting): setting.id
      }
    }

    case reddit(Reddit)
    case setting(Setting)

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

      case behavior, appearance, credentials, about, commentSwipe, postSwipe, accessibility, faq, general, themes, filteredSubreddits
    }
  }

  /// Shows `dest` with nothing stacked on it, even when it's the feed already selected.
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
  /// The subreddit feed this shows, by lowercased name. A subreddit known only by name (a quick
  /// action, the default feed) has its name as id, while the sidebar's cached one has Reddit's id,
  /// so `==` doesn't match the two.
  var subredditFeedName: String? {
    guard case let .reddit(.subFeed(sub)) = self else { return nil }
    // The front page, Popular, All and Saved aren't subreddits, even if one shares their name.
    if sub.data == nil, builtInFeedIDs.contains(sub.id) {
      return "feed:\(sub.id)"
    }
    return (sub.data?.display_name ?? sub.id).lowercased()
  }

  /// A subreddit or multireddit feed, which the sidebar can select.
  var isFeed: Bool {
    switch self {
    case .reddit(.subFeed), .reddit(.multiFeed): true
    default: false
    }
  }

  /// A subreddit feed with the subreddit's details, not just its name.
  var carriesSubredditData: Bool {
    if case let .reddit(.subFeed(sub)) = self {
      return sub.data != nil
    }
    return false
  }

  /// Fills in this feed's subreddit with the details `other` carries for the same feed; one that
  /// has its details takes only the account's state from it (`takingAccountState`). In place,
  /// so the feed view, the posts it loaded (which point at this subreddit) and its per-subreddit
  /// settings (compact mode, kept by the subreddit's id, which the details set) all keep using
  /// one subreddit, and the feed keeps its pages.
  func takeSubredditDetails(from other: Router.NavDest) {
    guard case let .reddit(.subFeed(sub)) = self, case let .reddit(.subFeed(otherSub)) = other,
          sub !== otherSub, let data = otherSub.data else { return }
    sub.data = sub.data.map { $0.takingAccountState(from: data) } ?? data
  }

  /// Whether both show the same feed, matching subreddits by name.
  func isSameFeed(as other: Router.NavDest) -> Bool {
    if let name = subredditFeedName, let otherName = other.subredditFeedName {
      return name == otherName
    }
    return self == other
  }
}

/// The feeds known by a fixed id rather than a subreddit name.
let builtInFeedIDs: Set<String> = ["home", "popular", "all", savedKeyword]
