//
//  WebPageScreen.swift
//  Helio
//
//  A web page opened from a link, shown in the app.
//

import SwiftUI
import WebKit

/// A web page opened from a link in a feed or a post (`Nav.openLink`): on Mac, where Safari's
/// view would leave the app, and beside the feed (the open iPhone Duo, iPad), where its sheet would
/// cover both columns. Pages keep their sites' data apart from the Reddit sign-in's, and
/// only until Helio next launches (`WebPageStorage`). The user's web extensions
/// (`WebExtensionRuntime`) run in them.
struct WebPageScreen: View {
  let url: URL
  @Environment(\.navColumn) private var navColumn
  /// The page, with its history, taken over from the screen this one replaces when the layout
  /// changes (`ScreenStates`).
  @State private var lease: ScreenStateLease<WebPageSlot>
  /// Made once the screen shows, not each time SwiftUI rebuilds this view.
  private var page: WebPageModel? {
    get { lease.model.page }
    nonmutating set { lease.model.page = newValue }
  }

  init(url: URL) {
    self.url = url
    _lease = State(initialValue: ScreenStates.shared.lease("web:\(url.absoluteString)") { WebPageSlot() })
  }

  var body: some View {
    Group {
      if let page {
        PageView(webView: page.webView)
          // To the bottom edge: the web view keeps its page clear of the home indicator itself, so
          // inside the safe area it left a black band under the page.
          .ignoresSafeArea(.container, edges: .bottom)
          .overlay(alignment: .top) {
            if page.isLoading {
              ProgressView(value: page.progress)
                .progressViewStyle(.linear)
            }
          }
          .navigationTitle(page.title.isEmpty ? url.host() ?? url.absoluteString : page.title)
          .navigationBarTitleDisplayMode(.inline)
          .commandTarget(CommandTargets.Target(kind: .web, column: navColumn, refresh: { page.webView.reload() }, actions: [.openInBrowser(page.url ?? url)]), updatingWith: page.url)
        #if !targetEnvironment(macCatalyst)
          // On Mac these are in the window toolbar (`MacTabToolbar`).
          .toolbar { PageToolbar(page: page, url: url) }
          // The bar's title and buttons follow the app's appearance, the page under it its own,
          // so in dark mode a light page under the bar's soft edge left white text on a light
          // band. The bar gets the app's own background instead.
          .toolbarBackground(Color(uiColor: .systemBackground), for: .navigationBar)
          .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        #endif
      } else {
        // Something to appear: an empty group never does, so the page would never be made.
        Color.clear
      }
    }
    .onAppear {
      lease.adopt()
      if let page {
        WebExtensionRuntime.shared.activate(page.webView)
      }
    }
    .task {
      guard page == nil else { return }
      // Once storage is cleared and the extensions loaded, which a link opened just after
      // launch would otherwise beat.
      await WebExtensionRuntime.shared.start()
      // Not for a screen left while it waited.
      if !Task.isCancelled, page == nil {
        page = WebPageModel(url: url)
      }
    }
  }
}

/// The page's previous and next page, reload or stop, share and Open in Browser, outside Mac.
private struct PageToolbar: ToolbarContent {
  let page: WebPageModel
  let url: URL

  var body: some ToolbarContent {
    let pageURL = page.url ?? url
    ToolbarItemGroup(placement: .bottomBar) {
      Button("Previous Page", systemImage: "chevron.backward") { page.webView.goBack() }
        .disabled(!page.canGoBack)
      Button("Next Page", systemImage: "chevron.forward") { page.webView.goForward() }
        .disabled(!page.canGoForward)
      Spacer()
      if page.isLoading {
        Button("Stop", systemImage: "xmark") { page.webView.stopLoading() }
      } else {
        Button("Reload", systemImage: "arrow.clockwise") { page.webView.reload() }
      }
    }
    ToolbarItemGroup(placement: .primaryAction) {
      ShareLink(item: pageURL)
      Button("Open in Browser", systemImage: "safari") {
        UIApplication.shared.open(pageURL)
      }
    }
  }
}

/// The page's web view, in a view of its own: a screen built for another layout takes the web view
/// over while the old screen's view may still be on screen, and taking the web view itself as the
/// representable's view would let the old one's teardown remove it.
private struct PageView: UIViewRepresentable {
  let webView: WKWebView

  func makeUIView(context _: Context) -> UIView {
    let container = UIView()
    attach(to: container)
    return container
  }

  /// Only once the web view has no other view: an old screen's view still updating would take it
  /// back from the new one.
  func updateUIView(_ container: UIView, context _: Context) {
    if webView.superview == nil {
      attach(to: container)
    }
  }

  private func attach(to container: UIView) {
    webView.frame = container.bounds
    webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.addSubview(webView)
  }
}

/// Where a screen keeps its page, so a screen that replaces it takes the page over.
@MainActor
@Observable
private final class WebPageSlot {
  var page: WebPageModel?
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
  private(set) var canGoBack = false
  private(set) var canGoForward = false
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
      webView.observe(\.canGoBack, options: .new) { [weak self] webView, _ in
        MainActor.assumeIsolated { self?.canGoBack = webView.canGoBack }
      },
      webView.observe(\.canGoForward, options: .new) { [weak self] webView, _ in
        MainActor.assumeIsolated { self?.canGoForward = webView.canGoForward }
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

  /// A link to another app (`mailto:`) goes to that app when the user clicks it; a page can't
  /// open another app on its own, through a redirect, a script or a frame. An extension's own
  /// pages (`webkit-extension:`) load in frames, but not as the page itself: WebKit loads those
  /// only in a web view made from the extension's configuration, which pages aren't.
  func webView(_: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
    guard let url = action.request.url, let scheme = url.scheme?.lowercased(),
          !["http", "https", "about", "data", "blob"].contains(scheme) else { return .allow }
    let mainFrame = action.targetFrame?.isMainFrame ?? true
    if scheme == "webkit-extension" {
      return mainFrame ? .cancel : .allow
    }
    if action.navigationType == .linkActivated, mainFrame {
      await UIApplication.shared.open(url)
    }
    return .cancel
  }

  /// A link meant for a new window (`target="_blank"`) opens in place: there's no other window
  /// to put it in.
  func webView(_ webView: WKWebView, createWebViewWith _: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures _: WKWindowFeatures) -> WKWebView? {
    webView.load(action.request)
    return nil
  }

  func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
    await JavaScriptDialogs.alert(message, by: frame, from: webView)
  }

  func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
    await JavaScriptDialogs.confirm(message, by: frame, from: webView)
  }

  func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
    await JavaScriptDialogs.prompt(prompt, defaultText: defaultText, by: frame, from: webView)
  }
}
