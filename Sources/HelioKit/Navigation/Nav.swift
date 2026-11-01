//
//  Nav.swift
//  Helio
//
//  Created by Igor Marcossi on 08/12/23.
//

import Combine
import Foundation
import SafariServices
import SwiftUI
import UIKit

@Observable
class Nav: Identifiable, Equatable {
  static let shared = Nav()

  /** <Util static functions for ease of use> */
  static func back() {
    Nav.shared.activeRouter.goBack()
  }

  static func to(_ dest: Router.NavDest, _ reset: Bool = false) {
    Nav.shared.activeRouter.navigateTo(dest, reset)
  }

  static func fullTo(_ tab: TabIdentifier, _ dest: Router.NavDest, _ reset: Bool = false) {
    Nav.shared.navigateTo(tab, dest, reset)
  }

  /// Shows `dest` as the posts tab's feed, as if chosen in the sidebar, replacing the screens
  /// stacked on the previous feed.
  static func selectFeed(_ dest: Router.NavDest) {
    Nav.shared.selectFeed(dest)
  }

  static func present(_ content: PresentingSheet?) {
    Nav.shared.presentingSheet = content
  }

  /* </Util static functions for ease of use> */

  private static func newRouterForTab(_ tab: TabIdentifier, _ id: UUID) -> Router {
    Router(id: "\(tab.rawValue)TabRouter-\(id.uuidString)")
  }

  enum TabIdentifier: String, Codable, Hashable, CaseIterable, Identifiable, Equatable {
    var id: String {
      self.rawValue
    }

    case posts, inbox, me, search, settings
  }

  enum PresentingSheet: Codable, Hashable, Identifiable, Equatable {
    case onboarding
    /// Signs in to Reddit on its website: a new account, or the credential's again.
    case redditSignIn(RedditCredential?)
    case editingCredential(RedditCredential)
    case editingTheme(HelioTheme)
    case selectText(String)

    var id: String {
      var newID = ""
      switch self {
      case let .editingCredential(cred): newID = cred.id.uuidString
      case .onboarding: newID = "onboarding"
      case let .redditSignIn(cred): newID = "reddit-sign-in-\(cred?.id.uuidString ?? "new")"
      case let .editingTheme(theme): newID = theme.id
      case let .selectText(text): newID = "select-text-\(text.hashValue)"
      }
      return "\(newID)-presenting-sheet-Nav"
    }
  }

  var id: UUID
  private var _suppressNextSameTabReset = false
  var activeTab: TabIdentifier {
    willSet {
      if activeTab == newValue {
        if _suppressNextSameTabReset {
          _suppressNextSameTabReset = false
        } else {
          self.activeRouter.resetNavPath()
        }
      }
    }
  }

  var routers: [TabIdentifier: Router]
  var presentingSheetsQueue: [PresentingSheet] = []
  var presentingSheet: PresentingSheet? {
    get { presentingSheetsQueue.isEmpty ? nil : presentingSheetsQueue[0] }
    set {
      if let newValue {
        if !presentingSheetsQueue.isEmpty, presentingSheetsQueue.first == newValue {
          presentingSheetsQueue[0] = newValue
        } else {
          presentingSheetsQueue.insert(newValue, at: 0)
        }
      } else if !presentingSheetsQueue.isEmpty {
        presentingSheetsQueue.removeFirst()
      }
    }
  }

  var activeRouter: Router {
    Nav.shared[activeTab]
  }

  private var cancellables = Set<AnyCancellable>()

  private init(activeTab: TabIdentifier = .posts) {
    let id = UUID()
    self.id = id
    self.activeTab = activeTab
    self.routers = Dictionary(uniqueKeysWithValues: TabIdentifier.allCases.map { ($0, Self.newRouterForTab($0, id)) })
  }

  func navigateTo(_ tab: TabIdentifier, _ dest: Router.NavDest, _ reset: Bool = true) {
    if tab != activeTab {
      _suppressNextSameTabReset = true
      activeTab = tab
    }
    routers[tab]?.navigateTo(dest, reset)
  }

  func selectFeed(_ dest: Router.NavDest) {
    if activeTab != .posts {
      _suppressNextSameTabReset = true
      activeTab = .posts
    }
    self[.posts].firstSelected = dest
  }

  subscript(tab: TabIdentifier) -> Router {
    let router = self.routers[tab] ?? Self.newRouterForTab(tab, id)
    if self.routers[tab] == nil {
      self.routers[tab] = router
    }
    return router
  }

  enum CodingKeys: String, CodingKey {
    case id, activeTab, routers
  }

  static func == (lhs: Nav, rhs: Nav) -> Bool {
    lhs.id == rhs.id
  }

  static func openURL(_ url: URL) {
    if url.scheme?.lowercased().contains(/http(s)?/) == true {
      let vc = SFSafariViewController(url: url)
      UIApplication.shared.firstKeyWindow?.rootViewController?.present(vc, animated: true)
    } else {
      UIApplication.shared.open(url)
    }
  }
}
