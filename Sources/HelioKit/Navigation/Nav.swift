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

  /// Opens `dest` in the active tab. Pass the column the request comes from (the
  /// `navColumn` environment value) so the posts split view opens it in the right one.
  static func to(_ dest: Router.NavDest, _ reset: Bool = false, from column: Router.Column? = nil) {
    Nav.shared.activeRouter.navigateTo(dest, reset, from: column)
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

  /// Asks the Search tab to show and focus its field, each time it's bumped (a Home Screen
  /// quick action), whether or not Search is already the tab shown.
  var searchFocusRequest = 0

  /// Switches tabs for the app, not the user. The tab view can echo the selection back as a
  /// same-tab tap, which would reset the new tab's screens; that echo is ignored, but only until
  /// the next turn, so a later real tap on the tab still resets it.
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
  }

  func navigateTo(_ tab: TabIdentifier, _ dest: Router.NavDest, _ reset: Bool = true) {
    if tab != activeTab {
      switchTab(to: tab)
    }
    routers[tab]?.navigateTo(dest, reset)
  }

  /// With `popToFeed`, screens opened from the feed are closed even when it's already selected,
  /// so the feed itself shows (a Home Screen quick action asks for the feed, not what's on it).
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
    }
    return router
  }

  enum CodingKeys: String, CodingKey {
    case id, activeTab, routers
  }

  static func == (lhs: Nav, rhs: Nav) -> Bool {
    lhs.id == rhs.id
  }

  /// Opens a link tapped in a feed or a post. In the posts tab, Reddit posts, subreddits and users
  /// open from the column the link sits in, like other taps there; on Mac, so do web pages. Anything
  /// else, or a Reddit link in another tab, goes through the app's URL handling as before.
  static func openLink(_ url: URL, from column: Router.Column?) {
    let dest = linkDestination(for: url)
    if let dest, Nav.shared.activeTab == .posts {
      withAnimation { Nav.to(dest, from: column) }
    } else if let dest {
      // From another tab it starts over on the posts tab, as the app's link handling does.
      withAnimation { Nav.fullTo(.posts, dest, true) }
    } else if opensWebPagesInApp, url.scheme?.lowercased().contains(/^https?$/) == true {
      // In the app on Mac: from the feed, beside it in the post column, like a post.
      withAnimation { Nav.to(.web(url), from: column) }
    } else {
      // Not something the app opens (a wiki page, any other site): the page itself.
      Nav.openURL(url)
    }
  }

  /// On Mac, Safari's view (`openURL`) sends the page to the default browser, out of the app, so
  /// links tapped in feeds and posts open as a screen of the app's (`WebPageScreen`) instead.
  static let opensWebPagesInApp: Bool = {
    #if targetEnvironment(macCatalyst)
      true
    #else
      false
    #endif
  }()

  /// The screen a link opens in the app: a post, a comment in its post, a subreddit or a user.
  /// Nil for anything else (wiki pages, other sites), which opens as the page itself.
  static func linkDestination(for url: URL) -> Router.NavDest? {
    switch parseRedditURL(appLink(for: url)) {
    case let .post(postID, subID): .reddit(.post(Post(id: postID, subID: subID)))
    case let .comment(commentID, postID, subID): .reddit(.postHighlighted(Post(id: postID, subID: subID), commentID))
    case let .subreddit(name): .reddit(.subFeed(Subreddit(id: name)))
    case let .user(username): .reddit(.user(User(id: username)))
    default: nil
    }
  }

  /// A Reddit web link (with `www.`, `old.` or neither) as an app link, which the parser reads;
  /// any other link unchanged.
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
  /// Links in Markdown text open from the column the text is in, like the app's other taps there
  /// (instead of through the app's URL handling, which doesn't know the column).
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
