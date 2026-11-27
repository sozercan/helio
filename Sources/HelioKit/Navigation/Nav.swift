import Combine
import Defaults
import Foundation
import SafariServices
import SwiftUI
import UIKit

@Observable
class Nav: Identifiable, Equatable {
  static let shared = Nav()

  static func back() {
    Nav.shared.activeRouter.goBack()
  }

  static func to(_ dest: Router.NavDest, _ reset: Bool = false, from column: Router.Column? = nil) {
    Nav.shared.activeRouter.navigateTo(dest, reset, from: column)
  }

  static func fullTo(_ tab: TabIdentifier, _ dest: Router.NavDest, _ reset: Bool = false) {
    Nav.shared.navigateTo(tab, dest, reset)
  }

  static func selectFeed(_ dest: Router.NavDest) {
    Nav.shared.selectFeed(dest)
  }

  static func present(_ content: PresentingSheet?) {
    Nav.shared.presentingSheet = content
  }

  @ObservationIgnored private var lastVisitedFeedByAccount: [UUID: String] = [:]
  @ObservationIgnored private var lastVisitedFeedByTab: [TabIdentifier: (accountID: UUID, feedName: String)] = [:]

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
    case redditSignIn(RedditCredential?)
    case editingCredential(RedditCredential)
    case editingTheme(HelioTheme)
    case selectText(String)
    case translateText(String)

    var id: String {
      var newID = ""
      switch self {
      case let .editingCredential(cred): newID = cred.id.uuidString
      case .onboarding: newID = "onboarding"
      case let .redditSignIn(cred): newID = "reddit-sign-in-\(cred?.id.uuidString ?? "new")"
      case let .editingTheme(theme): newID = theme.id
      case let .selectText(text): newID = "select-text-\(text.hashValue)"
      case let .translateText(text): newID = "translate-text-\(text.hashValue)"
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
    didSet {
      if let entry = lastVisitedFeedByTab[activeTab],
         entry.accountID == Defaults[.GeneralDefSettings].redditCredentialSelectedID
      {
        recordVisitedFeed(entry.feedName, for: activeTab)
      }
    }
  }

  var routers: [TabIdentifier: Router]

  var searchFocusRequest = 0

  private func switchTab(to tab: TabIdentifier) {
    _suppressNextSameTabReset = true
    activeTab = tab
    Task { @MainActor [weak self] in
      self?._suppressNextSameTabReset = false
    }
  }

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
    for (tab, router) in routers {
      observeFeedNavigation(on: router, tab: tab)
    }
  }

  private func observeFeedNavigation(on router: Router, tab: TabIdentifier) {
    router.onFeedVisit = { [weak self] feedName in
      self?.recordVisitedFeed(feedName, for: tab)
    }
  }

  private func recordVisitedFeed(_ feedName: String, for tab: TabIdentifier) {
    guard let accountID = Defaults[.GeneralDefSettings].redditCredentialSelectedID else { return }
    lastVisitedFeedByAccount[accountID] = feedName
    lastVisitedFeedByTab[tab] = (accountID, feedName)
    guard Defaults[.BehaviorDefSettings].restoreReadingSession else { return }
    ReadingSessionStore.save(feedName: feedName, accountID: accountID)
  }

  func currentFeedName(for accountID: UUID?) -> String? {
    guard let accountID else { return nil }
    return lastVisitedFeedByAccount[accountID]
  }

  func navigateTo(_ tab: TabIdentifier, _ dest: Router.NavDest, _ reset: Bool = true) {
    if tab != activeTab {
      switchTab(to: tab)
    }
    routers[tab]?.navigateTo(dest, reset)
  }

  func selectFeed(_ dest: Router.NavDest, popToFeed: Bool = false) {
    if activeTab != .posts {
      switchTab(to: .posts)
    }
    if popToFeed {
      self[.posts].showFeedRoot(dest)
    } else {
      self[.posts].firstSelected = dest
    }
  }

  subscript(tab: TabIdentifier) -> Router {
    let router = self.routers[tab] ?? Self.newRouterForTab(tab, id)
    if self.routers[tab] == nil {
      self.routers[tab] = router
      observeFeedNavigation(on: router, tab: tab)
    }
    return router
  }

  enum CodingKeys: String, CodingKey {
    case id, activeTab, routers
  }

  static func == (lhs: Nav, rhs: Nav) -> Bool {
    lhs.id == rhs.id
  }

  @MainActor
  static func openLink(_ url: URL, from column: Router.Column?) {
    let dest = linkDestination(for: url)
    if let dest, Nav.shared.activeTab == .posts {
      withAnimation { Nav.to(dest, from: column) }
    } else if let dest {
      withAnimation { Nav.fullTo(.posts, dest, true) }
    } else if opensWebPageInApp(from: column), url.scheme?.lowercased().contains(/^https?$/) == true {
      withAnimation { Nav.to(.web(url), from: column) }
    } else {
      Nav.openURL(url)
    }
  }

  static let opensWebPagesInApp: Bool = {
    #if targetEnvironment(macCatalyst)
      true
    #else
      false
    #endif
  }()

  @MainActor
  static func opensWebPageInApp(from column: Router.Column?) -> Bool {
    if opensWebPagesInApp || WebExtensionStore.shared.hasEnabledExtensions {
      return true
    }
    return column != nil && Nav.shared.activeTab == .posts && Nav.shared[.posts].showsPostBesideFeed
  }

  static func linkDestination(for url: URL) -> Router.NavDest? {
    switch parseRedditURL(appLink(for: url)) {
    case let .post(postID, subID): .reddit(.post(Post(id: postID, subID: subID)))
    case let .comment(commentID, postID, subID): .reddit(.postHighlighted(Post(id: postID, subID: subID), commentID))
    case let .subreddit(name): .reddit(.subFeed(Subreddit(id: name)))
    case let .user(username): .reddit(.user(User(id: username)))
    default: nil
    }
  }

  static func appLink(for url: URL) -> String {
    url.absoluteString.replacingOccurrences(of: #"^https?://(www\.|old\.)?reddit\.com/"#, with: "helioapp://", options: .regularExpression)
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

extension View {
  func opensLinksInItsColumn() -> some View {
    modifier(ColumnLinkOpener())
  }
}

private struct ColumnLinkOpener: ViewModifier {
  @Environment(\.navColumn) private var navColumn

  func body(content: Content) -> some View {
    content.environment(\.openURL, OpenURLAction { url in
      Nav.openLink(url, from: navColumn)
      return .handled
    })
  }
}
