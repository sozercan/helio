//
//  RedditWebLoginView.swift
//  Helio
//

import SwiftUI
import WebKit

/// Signs in to Reddit on its own website, then saves the session as `credential`: a new
/// credential, or one whose session ended. No API key needed.
struct RedditWebLoginView: View {
  var credential: RedditCredential
  /// Shown when this is the root of its sheet rather than a pushed page.
  var showsCancel = false

  @State private var phase: Phase = .browsing
  /// Bumped to start over with an empty browser.
  @State private var attempt = 0

  private enum Phase { case browsing, finishing, failed }

  var body: some View {
    RedditWebLoginWebView { cookies, userAgent in
      Task { await finish(cookies: cookies, userAgent: userAgent) }
    }
    .id(attempt)
    .overlay {
      if phase != .browsing {
        VStack(spacing: 16) {
          if phase == .finishing {
            ProgressView()
            Text("Signing in…").fontSize(17, .semibold)
          } else {
            Image(systemName: "exclamationmark.triangle.fill").fontSize(40).foregroundStyle(.orange)
            Text("Reddit didn't let Helio sign in").fontSize(17, .semibold)
            Button("Try again", systemImage: "arrow.clockwise") {
              attempt += 1
              phase = .browsing
            }
            .buttonStyle(.action)
          }
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
      }
    }
    .navigationTitle("Sign in to Reddit")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if showsCancel {
        ToolbarItem(placement: .topBarLeading) { Button("Cancel") { Nav.present(nil) } }
      }
    }
  }

  @MainActor
  private func finish(cookies: String, userAgent: String) async {
    phase = .finishing
    guard let signedIn = await RedditWebSession.signIn(credential, cookies: cookies, userAgent: userAgent) else {
      phase = .failed
      return
    }
    // Signing in to an account Helio already has updates that credential instead of adding another.
    var saved = signedIn
    if let existing = RedditCredentialsManager.shared.credentials.first(where: {
      $0.id != signedIn.id && $0.isWebSession && $0.userName?.lowercased() == signedIn.userName?.lowercased()
    }) {
      saved.id = existing.id
    }
    saved.save()
    Nav.present(nil)
  }
}

/// A browser on reddit.com's sign-in page with its own empty cookie store, so each sign-in
/// starts signed out. It reports the session once Reddit says someone is signed in.
private struct RedditWebLoginWebView: UIViewRepresentable {
  var onSignedIn: @MainActor (_ cookies: String, _ userAgent: String) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onSignedIn: onSignedIn)
  }

  func makeUIView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = context.coordinator
    webView.uiDelegate = context.coordinator
    webView.load(URLRequest(url: RedditWebSession.loginURL))
    context.coordinator.startPolling(webView)
    return webView
  }

  func updateUIView(_: WKWebView, context _: Context) {}

  static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
    coordinator.stop()
    webView.stopLoading()
  }

  @MainActor
  final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let onSignedIn: @MainActor (String, String) -> Void
    private var poll: Task<Void, Never>?
    private var pageLoaded = false
    private var checking = false
    private var done = false

    /// Asks Reddit, from the page's origin so its cookies go along, who is signed in.
    private static let signedInUserScript = """
    try {
      const response = await fetch('/api/me.json', { credentials: 'include' });
      if (!response.ok) { return ''; }
      const body = await response.json();
      return (body && body.data && body.data.name) ? body.data.name : '';
    } catch (e) { return ''; }
    """

    init(onSignedIn: @escaping @MainActor (String, String) -> Void) {
      self.onSignedIn = onSignedIn
    }

    /// Reddit's sign-in form submits without navigating, so page loads alone can miss it.
    func startPolling(_ webView: WKWebView) {
      poll = Task { [weak self, weak webView] in
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(2))
          guard let self, let webView, !Task.isCancelled else { return }
          await self.checkSignedIn(webView)
        }
      }
    }

    func stop() {
      done = true
      poll?.cancel()
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
      pageLoaded = true
      Task { await checkSignedIn(webView) }
    }

    /// Opens sign-in popups (such as "Continue with Apple") in the same browser.
    func webView(_ webView: WKWebView, createWebViewWith _: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures _: WKWindowFeatures) -> WKWebView? {
      if navigationAction.targetFrame == nil {
        webView.load(navigationAction.request)
      }
      return nil
    }

    private func checkSignedIn(_ webView: WKWebView) async {
      guard pageLoaded, !checking, !done, webView.url?.host?.hasSuffix("reddit.com") == true else { return }
      checking = true
      defer { checking = false }

      let name = try? await webView.callAsyncJavaScript(Self.signedInUserScript, contentWorld: .page) as? String
      guard let name, !name.isEmpty, !done else { return }
      let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
      guard let header = RedditWebSession.cookieHeader(from: cookies), !done else { return }
      let userAgent = await (try? webView.callAsyncJavaScript("return navigator.userAgent", contentWorld: .page) as? String) ?? RedditCredential.defaultUserAgent()
      guard !done else { return }
      stop()
      onSignedIn(header, userAgent)
    }
  }
}
