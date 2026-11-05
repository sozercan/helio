//
//  WebPageScreen.swift
//  Helio
//
//  A web page opened from a link, shown in the app.
//

import SwiftUI
import WebKit

/// A web page opened from a link in a feed or a post (`Nav.openLink`), on Mac, where Safari's
/// view would leave the app. Each page gets its own data store, kept in memory only, so what a
/// site stores goes with the screen and never meets the Reddit sign-in's cookies.
struct WebPageScreen: View {
  let url: URL
  @Environment(\.navColumn) private var navColumn
  /// Made once the screen shows, not each time SwiftUI rebuilds this view.
  @State private var page: WebPage?

  var body: some View {
    Group {
      if let page {
        WebView(page)
          .webViewBackForwardNavigationGestures(.enabled)
          .overlay(alignment: .top) {
            if page.isLoading {
              ProgressView(value: page.estimatedProgress)
                .progressViewStyle(.linear)
            }
          }
          .navigationTitle(page.title.isEmpty ? url.host() ?? url.absoluteString : page.title)
          .navigationBarTitleDisplayMode(.inline)
          .commandTarget(CommandTargets.Target(kind: .web, column: navColumn, refresh: { _ = page.reload() }, actions: [.openInBrowser(page.url ?? url)]), updatingWith: page.url)
      } else {
        // Something to appear: an empty group never does, so the page would never be made.
        Color.clear
      }
    }
    .onAppear {
      guard page == nil else { return }
      let page = Self.makePage()
      _ = page.load(URLRequest(url: url))
      self.page = page
    }
  }

  private static func makePage() -> WebPage {
    var configuration = WebPage.Configuration()
    configuration.websiteDataStore = .nonPersistent()
    let opener = PageOpener()
    let page = WebPage(configuration: configuration, navigationDecider: opener)
    opener.page = page
    return page
  }
}

/// Keeps a page's navigation in its screen: a link meant for a new window (`target="_blank"`)
/// opens in place, as there's no other window to put it in, and one to another app (`mailto:`)
/// goes to that app when the user clicks it. A page can't open another app on its own, through a
/// redirect, a script or a frame.
@MainActor
private final class PageOpener: WebPage.NavigationDeciding {
  weak var page: WebPage?

  func decidePolicy(for action: WebPage.NavigationAction, preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
    guard let url = action.request.url else { return .allow }
    if let scheme = url.scheme?.lowercased(), !["http", "https", "about", "data", "blob"].contains(scheme) {
      if action.navigationType == .linkActivated, action.target?.isMainFrame ?? true {
        await UIApplication.shared.open(url)
      }
      return .cancel
    }
    if action.target == nil {
      _ = page?.load(action.request)
      return .cancel
    }
    return .allow
  }
}
