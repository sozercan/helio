import Defaults
import SwiftUI
import WebKit

struct RedditWebLoginView: View {
  var credential: RedditCredential
  var showsCancel = false

  @State private var phase: Phase = .browsing
  @State private var attempt = 0

  private enum Phase: Equatable {
    case browsing, finishing, failed
    case wrongAccount(signedIn: RedditCredential)
  }

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
    var saved = signedIn
    if let existing = RedditCredentialsManager.shared.credentials.first(where: {
      $0.id != signedIn.id && $0.isWebSession && $0.userName?.lowercased() == signedIn.userName?.lowercased()
    }) {
      saved.id = existing.id
    }
    let selectedID = Defaults[.GeneralDefSettings].redditCredentialSelectedID
    saved.save()
    if selectedID == nil || selectedID == saved.id {
      RedditCredentialsManager.shared.updateMe()
    }
    Nav.present(nil)
  }
}

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
    private var popup: WKWebView?
    private var poll: Task<Void, Never>?
    private var pageLoaded = false
    private var checking = false
    private var done = false
    private var reportedSession: String?

    init(onSession: @escaping @MainActor (String, String) async -> Bool, onLoadFailed: @escaping @MainActor () -> Void) {
      self.onSession = onSession
      self.onLoadFailed = onLoadFailed
    }

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
      guard webView !== popup, !pageLoaded, (error as? URLError)?.code != .cancelled else { return }
      onLoadFailed()
    }

    private static let signInPopupHosts = ["appleid.apple.com", "accounts.google.com"]

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
