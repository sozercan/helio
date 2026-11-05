//
//  RedditWebLoginView.swift
//  Helio
//

import Defaults
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

  private enum Phase: Equatable {
    case browsing, finishing, failed
    /// Signed in to `signedIn`'s account instead of the one `credential` is for.
    case wrongAccount(signedIn: RedditCredential)
  }

  /// The account `credential` is for, when it's a saved one: signing in again has to keep it.
  private var expectedUserName: String? {
    credential.isInKeychain() ? credential.userName : nil
  }

  var body: some View {
    RedditWebLoginWebView { cookies, userAgent in
      await finish(cookies: cookies, userAgent: userAgent)
    } onLoadFailed: {
      phase = .failed
    }
    .id(attempt)
    .overlay {
      if phase != .browsing {
        VStack(spacing: 16) {
          switch phase {
          case .browsing:
            EmptyView()
          case .finishing:
            ProgressView()
            Text("Signing in…").fontSize(17, .semibold)
          case .failed:
            Image(systemName: "exclamationmark.triangle.fill").fontSize(40).foregroundStyle(.orange)
            Text("Couldn't sign in to Reddit").fontSize(17, .semibold)
            Button("Try again", systemImage: "arrow.clockwise", action: startOver)
              .buttonStyle(.action)
          case let .wrongAccount(signedIn):
            Image(systemName: "person.crop.circle.badge.exclamationmark.fill").fontSize(40).foregroundStyle(.orange)
            Text("You signed in as u/\(signedIn.userName ?? "?"), not u/\(expectedUserName ?? "?")").fontSize(17, .semibold)
            Button("Sign in as u/\(expectedUserName ?? "?")", systemImage: "arrow.clockwise", action: startOver)
              .buttonStyle(.action)
            Button("Add u/\(signedIn.userName ?? "?") as another account") {
              var added = signedIn
              added.id = UUID()
              save(added)
            }
            .buttonStyle(.actionOutlined)
          }
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
      }
    }
    .navigationTitle(expectedUserName.map { "Sign in as u/\($0)" } ?? "Sign in to Reddit")
    .navigationBarTitleDisplayMode(.inline)
    // Signing in saves the credential and closes the sheet, so leaving midway isn't offered.
    .navigationBarBackButtonHidden(phase == .finishing)
    .interactiveDismissDisabled(phase == .finishing)
    .toolbar {
      if showsCancel, phase != .finishing {
        ToolbarItem(placement: .topBarLeading) { Button("Cancel") { Nav.present(nil) } }
      }
    }
  }

  private func startOver() {
    attempt += 1
    phase = .browsing
  }

  /// Returns whether the browser is done: `false` when the cookies turned out to be a signed-out
  /// visitor's, so it keeps watching for the sign-in.
  @MainActor
  private func finish(cookies: String, userAgent: String) async -> Bool {
    phase = .finishing
    switch await RedditWebSession.signIn(credential, cookies: cookies, userAgent: userAgent) {
    case .signedOut:
      phase = .browsing
      return false
    case .failed:
      phase = .failed
    case let .signedIn(signedIn):
      if let expectedUserName, signedIn.userName?.lowercased() != expectedUserName.lowercased() {
        phase = .wrongAccount(signedIn: signedIn)
      } else {
        save(signedIn)
      }
    }
    return true
  }

  private func save(_ signedIn: RedditCredential) {
    // Signing in to an account Helio already has updates that credential instead of adding another.
    var saved = signedIn
    if let existing = RedditCredentialsManager.shared.credentials.first(where: {
      $0.id != signedIn.id && $0.isWebSession && $0.userName?.lowercased() == signedIn.userName?.lowercased()
    }) {
      saved.id = existing.id
    }
    // The account in use (or the first one, which becomes it) loads its profile again: one
    // signed out had lost it, and selecting the same credential doesn't reload it.
    let selectedID = Defaults[.GeneralDefSettings].redditCredentialSelectedID
    saved.save()
    if selectedID == nil || selectedID == saved.id {
      RedditCredentialsManager.shared.updateMe()
    }
    Nav.present(nil)
  }
}

/// A browser on reddit.com's sign-in page with its own empty cookie store, so each sign-in
/// starts signed out. It reports each new session cookie; `onSession` returns whether that was
/// the sign-in.
private struct RedditWebLoginWebView: UIViewRepresentable {
  var onSession: @MainActor (_ cookies: String, _ userAgent: String) async -> Bool
  var onLoadFailed: @MainActor () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onSession: onSession, onLoadFailed: onLoadFailed)
  }

  func makeUIView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = context.coordinator
    webView.uiDelegate = context.coordinator
    webView.allowsBackForwardNavigationGestures = true
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
    private let onSession: @MainActor (String, String) async -> Bool
    private let onLoadFailed: @MainActor () -> Void
    /// A sign-in popup, such as "Continue with Apple", shown over the page that opened it.
    private var popup: WKWebView?
    private var poll: Task<Void, Never>?
    private var pageLoaded = false
    private var checking = false
    private var done = false
    /// The session cookie last reported, so a signed-out visitor's isn't sent to the token
    /// service every poll.
    private var reportedSession: String?

    init(onSession: @escaping @MainActor (String, String) async -> Bool, onLoadFailed: @escaping @MainActor () -> Void) {
      self.onSession = onSession
      self.onLoadFailed = onLoadFailed
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
      closePopup()
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
      guard webView !== popup else { return }
      pageLoaded = true
      Task { await checkSignedIn(webView) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
      // Only the sign-in page failing to load at all leaves nothing to tap.
      guard webView !== popup, !pageLoaded, (error as? URLError)?.code != .cancelled else { return }
      onLoadFailed()
    }

    /// Hosts whose sign-in popups report back to the page that opened them.
    private static let signInPopupHosts = ["appleid.apple.com", "accounts.google.com"]

    /// Sign-in popups keep their opener and cover it until they close. Other new-window links,
    /// such as the privacy policy, open in place, where swiping back returns to the sign-in.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures _: WKWindowFeatures) -> WKWebView? {
      guard let host = navigationAction.request.url?.host?.lowercased(), Self.signInPopupHosts.contains(host), popup == nil else {
        webView.load(navigationAction.request)
        return nil
      }
      let popup = WKWebView(frame: webView.bounds, configuration: configuration)
      popup.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      popup.navigationDelegate = self
      popup.uiDelegate = self
      webView.addSubview(popup)
      self.popup = popup
      return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
      if webView === popup {
        closePopup()
      }
    }

    private func closePopup() {
      popup?.stopLoading()
      popup?.removeFromSuperview()
      popup = nil
    }

    /// Reads the browser's cookies rather than asking the page, which reddit.com doesn't let
    /// scripts fetch from. Whether a session cookie is a sign-in is the token service's call.
    private func checkSignedIn(_ webView: WKWebView) async {
      guard pageLoaded, !checking, !done else { return }
      checking = true
      defer { checking = false }

      let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
      guard
        let session = RedditWebSession.sessionCookieValue(from: cookies), session != reportedSession,
        let header = RedditWebSession.cookieHeader(from: cookies), !done
      else { return }
      let userAgent = await (try? webView.callAsyncJavaScript("return navigator.userAgent", contentWorld: .page) as? String) ?? RedditCredential.defaultUserAgent()
      guard !done else { return }
      reportedSession = session
      if await onSession(header, userAgent) {
        stop()
      }
    }
  }
}
