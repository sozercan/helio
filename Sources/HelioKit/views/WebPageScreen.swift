import SwiftUI
import WebKit

struct WebPageScreen: View {
  let url: URL
  @Environment(\.navColumn) private var navColumn
  @Environment(\.screenStateScope) private var screenStateScope
  @State private var lease: ScreenStateLease<WebPageSlot>
  private var page: WebPageModel? {
    get { lease.model.page }
    nonmutating set { lease.model.page = newValue }
  }

  private var showsBesideFeed: Bool {
    navColumn == .post && Nav.shared[.posts].showsPostBesideFeed
  }

  init(url: URL) {
    self.url = url
    _lease = State(initialValue: ScreenStates.shared.lease("web:\(url.absoluteString)", owner: nil) { WebPageSlot() })
  }

  var body: some View {
    Group {
      if let page, lease.settled {
        PageView(webView: page.webView)
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
          .toolbar { PageToolbar(page: page, url: url) }
          .toolbarBackground(Color(uiColor: .systemBackground), for: .navigationBar)
          .toolbarBackgroundVisibility(.visible, for: .navigationBar)
          .toolbar(showsBesideFeed ? .automatic : .hidden, for: .tabBar)
        #endif
      } else {
        Color.clear
      }
    }
    .onAppear {
      lease.adopt(in: screenStateScope)
      if let page {
        WebExtensionRuntime.shared.activate(page.webView)
      }
    }
    .task {
      guard page == nil else { return }
      await WebExtensionRuntime.shared.start()
      if !Task.isCancelled, page == nil {
        page = WebPageModel(url: url)
      }
    }
  }
}

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

private struct PageView: UIViewRepresentable {
  let webView: WKWebView

  func makeUIView(context _: Context) -> UIView {
    let container = UIView()
    attach(to: container)
    return container
  }

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

@MainActor
@Observable
private final class WebPageSlot {
  var page: WebPageModel?
}

enum WebPageStorage {
  private static let id = UUID(uuidString: "5C0F4E2B-8D3A-4B6E-9A71-2F6D8C1B4E39")!

  @MainActor static let store = WKWebsiteDataStore(forIdentifier: id)

  @MainActor
  static func clear() async {
    await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
  }
}

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
    let webView = webView
    Task { @MainActor in WebExtensionRuntime.shared.detach(webView) }
  }

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
