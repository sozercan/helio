//
//  WebPageScreen.swift
//  Helio
//
//  A web page opened from a link, shown in the app.
//

import SwiftUI
import WebKit

/// A web page opened from a link in a feed or a post (`Nav.openLink`), on Mac, where Safari's
/// view would leave the app. Pages keep their sites' data apart from the Reddit sign-in's, and
/// only until Helio next launches (`WebPageStorage`). The user's web extensions
/// (`WebExtensionRuntime`) run in them.
struct WebPageScreen: View {
  let url: URL
  @Environment(\.navColumn) private var navColumn
  /// Made once the screen shows, not each time SwiftUI rebuilds this view.
  @State private var page: WebPageModel?

  var body: some View {
    Group {
      if let page {
        PageView(webView: page.webView)
          .overlay(alignment: .top) {
            if page.isLoading {
              ProgressView(value: page.progress)
                .progressViewStyle(.linear)
            }
          }
          .navigationTitle(page.title.isEmpty ? url.host() ?? url.absoluteString : page.title)
          .navigationBarTitleDisplayMode(.inline)
          .commandTarget(CommandTargets.Target(kind: .web, column: navColumn, refresh: { page.webView.reload() }, actions: [.openInBrowser(page.url ?? url)]), updatingWith: page.url)
      } else {
        // Something to appear: an empty group never does, so the page would never be made.
        Color.clear
      }
    }
    .onAppear {
      if let page {
        WebExtensionRuntime.shared.activate(page.webView)
      }
    }
    .task {
      guard page == nil else { return }
      // Once storage is cleared and the extensions loaded, which a link opened just after
      // launch would otherwise beat.
      await WebExtensionRuntime.shared.start()
      if page == nil {
        page = WebPageModel(url: url)
      }
    }
  }
}

private struct PageView: UIViewRepresentable {
  let webView: WKWebView

  func makeUIView(context _: Context) -> WKWebView {
    webView
  }

  func updateUIView(_: WKWebView, context _: Context) {}
}

/// Where pages keep their sites' data (cookies, storage, cache): one store of their own, apart
/// from the Reddit sign-in's, cleared at each launch. Not one kept only in memory, which would
/// keep even less: WebKit runs no extension in such a page.
enum WebPageStorage {
  /// A fixed id, so each launch finds and clears the last one's store.
  private static let id = UUID(uuidString: "5C0F4E2B-8D3A-4B6E-9A71-2F6D8C1B4E39")!

  @MainActor static let store = WKWebsiteDataStore(forIdentifier: id)

  /// Drops what sites stored before this launch, before the first page opens
  /// (`WebExtensionRuntime.start`).
  @MainActor
  static func clear() async {
    await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
  }
}

/// A page's web view and what the screen shows of it.
@MainActor
@Observable
private final class WebPageModel: NSObject, WKNavigationDelegate, WKUIDelegate {
  let webView: WKWebView
  private(set) var title = ""
  private(set) var url: URL?
  private(set) var isLoading = false
  private(set) var progress = 0.0
  @ObservationIgnored private var observations: [NSKeyValueObservation] = []

  init(url: URL) {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = WebPageStorage.store
    let runtime = WebExtensionRuntime.shared
    if runtime.hasExtensions {
      configuration.webExtensionController = runtime.controller
    }
    webView = WKWebView(frame: .zero, configuration: configuration)
    webView.allowsBackForwardNavigationGestures = true
    super.init()
    webView.navigationDelegate = self
    webView.uiDelegate = self
    observations = [
      webView.observe(\.title, options: .new) { [weak self] webView, _ in
        MainActor.assumeIsolated {
          self?.title = webView.title ?? ""
          WebExtensionRuntime.shared.pageChanged(webView, .title)
        }
      },
      webView.observe(\.url, options: .new) { [weak self] webView, _ in
        MainActor.assumeIsolated {
          self?.url = webView.url
          WebExtensionRuntime.shared.pageChanged(webView, .URL)
        }
      },
      webView.observe(\.isLoading, options: .new) { [weak self] webView, _ in
        MainActor.assumeIsolated {
          self?.isLoading = webView.isLoading
          WebExtensionRuntime.shared.pageChanged(webView, .loading)
        }
      },
      webView.observe(\.estimatedProgress, options: .new) { [weak self] webView, _ in
        MainActor.assumeIsolated { self?.progress = webView.estimatedProgress }
      },
    ]
    runtime.attach(webView)
    webView.load(URLRequest(url: url))
  }

  deinit {
    // The screen is gone for good: so is its tab.
    let webView = webView
    Task { @MainActor in WebExtensionRuntime.shared.detach(webView) }
  }

  /// A link to another app (`mailto:`) goes to that app. An extension's own pages
  /// (`webkit-extension:`) load here, through the controller.
  func webView(_: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
    guard let url = action.request.url, let scheme = url.scheme?.lowercased(),
          !["http", "https", "about", "data", "blob", "webkit-extension"].contains(scheme) else { return .allow }
    await UIApplication.shared.open(url)
    return .cancel
  }

  /// A link meant for a new window (`target="_blank"`) opens in place: there's no other window
  /// to put it in.
  func webView(_ webView: WKWebView, createWebViewWith _: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures _: WKWindowFeatures) -> WKWebView? {
    webView.load(action.request)
    return nil
  }
}
