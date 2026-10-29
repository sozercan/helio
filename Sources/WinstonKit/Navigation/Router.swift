//
//  Router.swift
//  winston
//
//  Created by Igor Marcossi on 05/08/23.
//

import Foundation
import SwiftUI

class ViewControllerHolder: Identifiable, Equatable {
  static func == (lhs: ViewControllerHolder, rhs: ViewControllerHolder) -> Bool {
    lhs.id == rhs.id
  }
  
  var id: String { "ctrl-holder-\(self.routerID)" }
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
  
  var firstSelected: NavDest? {
    get { fullPath.isEmpty ? nil : fullPath[0] }
    set {
      if let newValue = newValue {
        if fullPath.count == 0 { fullPath.append(newValue) } else { fullPath[0] = newValue } } else { fullPath = [] }
    }
  }
  var fullPath: [NavDest] = [] {
    didSet {
      if fullPath.isEmpty != isAtRoot { isAtRoot = fullPath.isEmpty }
    }
  }
  var path: [NavDest] {
    get { Array(self.fullPath.dropFirst()) }
    set {
      if fullPath.isEmpty { self.fullPath = newValue } else { self.fullPath = [fullPath[0]] + newValue }
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
  
  func goBack() { if self.fullPath.count > 0 { _ = withAnimation { self.fullPath.removeLast() } } }
  func resetNavPath() { withAnimation { self.fullPath.removeAll() } }
  func navigateTo(_ dest: NavDest, _ reset: Bool = false) { self.path = reset ? [dest] : self.path + [dest] }
  
  enum NavDest: Hashable, Codable, Identifiable {
    var id: String {
      switch self {
      case .reddit(let reddit): return reddit.id
      case .setting(let setting): return setting.id
      }
    }
    case reddit(Reddit)
    case setting(Setting)
    
    enum Reddit: Hashable, Codable, Identifiable {
      var id: String {
        switch self {
        case .post(let post): return post.id
        case .postHighlighted(let post, _): return post.id
        case .subFeed(let subreddit): return subreddit.id
        case .subInfo(let subreddit): return subreddit.id
        case .multiFeed(let multi): return multi.id
        case .multiInfo(let multi): return multi.id
        case .user(let user): return user.id
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
      var id: String { self.rawValue }
      case behavior, appearance, credentials, about, commentSwipe, postSwipe, accessibility, faq, general, themes, filteredSubreddits
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
