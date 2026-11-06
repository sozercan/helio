//
//  WebExtensionRuntime.swift
//  Helio
//
//  Runs the user's web extensions in the web pages the app shows.
//

import Foundation
import os
import WebKit

/// Loads the enabled web extensions (`WebExtensionStore`) once, at launch, into a controller the
/// app's web pages (`WebPageScreen`) share. WebKit can't unload an extension, so changes to the
/// list wait for the next launch.
///
/// The controller alone doesn't run an extension's scripts in a page: WebKit asks the app for
/// the browser's tabs and windows, and finds a page's web view through its tab. Helio has no
/// tabs, so each page shown registers as a tab of one window.
@MainActor
@Observable
final class WebExtensionRuntime: NSObject {
  static let shared = WebExtensionRuntime()

  /// Its default data store, which extensions' cookie and data APIs reach, is the pages' own
  /// (`WebPageStorage`), not the app's. Extensions' own pages (background, settings) keep their
  /// data in a store of their own instead, which the launch's clearing of the pages' leaves alone.
  @ObservationIgnored let controller: WKWebExtensionController = {
    let configuration = WKWebExtensionController.Configuration.default()
    configuration.defaultWebsiteDataStore = WebPageStorage.store
    let extensionPages = WKWebViewConfiguration()
    extensionPages.websiteDataStore = WKWebsiteDataStore(forIdentifier: WebExtensionRuntime.extensionPagesStoreID)
    configuration.webViewConfiguration = extensionPages
    return WKWebExtensionController(configuration: configuration)
  }()

  /// Fixed, so extensions' pages find their data again each launch.
  private static let extensionPagesStoreID = UUID(uuidString: "8E3B1F64-2C7D-4A95-B0E8-6D4F2A9C1E73")!

  @ObservationIgnored private let window = HostWindow()
  @ObservationIgnored private var tabs: [ObjectIdentifier: HostTab] = [:]
  @ObservationIgnored private var startTask: Task<Void, Never>?
  @ObservationIgnored private let logger = Logger(subsystem: "com.sertacozercan.helio", category: "WebExtensions")

  /// The loaded extensions, by their id in the store. Observed: the Extensions panel shows
  /// what loaded, which can finish after it opens.
  private(set) var contexts: [String: WKWebExtensionContext] = [:]
  /// Why an enabled extension didn't load, by its id in the store.
  private(set) var loadErrors: [String: String] = [:]

  override private init() {
    super.init()
    controller.delegate = self
  }

  /// Whether pages should run extensions: any loaded.
  var hasExtensions: Bool {
    !contexts.isEmpty
  }

  /// Gets pages ready, once per launch: drops what sites stored last time (`WebPageStorage`),
  /// then loads the enabled extensions. Each page waits for it, so none opens with the last
  /// launch's site data or without the extensions, whenever it's opened.
  func start(store: WebExtensionStore = .shared) async {
    if startTask == nil {
      startTask = Task {
        await WebPageStorage.clear()
        for (id, url) in store.enabledFolders {
          await load(id: id, from: url)
        }
      }
    }
    await startTask?.value
  }

  private func load(id: String, from url: URL) async {
    do {
      let webExtension = try await WKWebExtension(resourceBaseURL: url)
      let context = WKWebExtensionContext(for: webExtension)
      // Its storage and its pages' origin stay the same across launches.
      context.uniqueIdentifier = id
      // The user chose to add it, and Helio has no prompts to ask with: it gets what it asks for,
      // including what it may ask for later (uBlock Origin Lite needs every site to hide page
      // elements, not just block requests).
      for permission in webExtension.requestedPermissions.union(webExtension.optionalPermissions) {
        context.setPermissionStatus(.grantedExplicitly, for: permission)
      }
      for pattern in webExtension.requestedPermissionMatchPatterns.union(webExtension.optionalPermissionMatchPatterns) {
        context.setPermissionStatus(.grantedExplicitly, for: pattern)
      }
      try controller.load(context)
      contexts[id] = context
      if webExtension.hasBackgroundContent {
        // Loaded, but not working: the panel says so.
        try await context.loadBackgroundContent()
      }
      logger.info("Loaded extension \(webExtension.displayName ?? id, privacy: .public) \(webExtension.version ?? "", privacy: .public)")
    } catch {
      loadErrors[id] = error.localizedDescription
      logger.error("Couldn't load extension \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: Pages as tabs

  /// Makes a page a tab extensions can reach, and the active one.
  func attach(_ webView: WKWebView) {
    guard webView.configuration.webExtensionController === controller, tabs[ObjectIdentifier(webView)] == nil else { return }
    let tab = HostTab(webView: webView, window: window)
    tabs[ObjectIdentifier(webView)] = tab
    let firstTab = window.tabs.isEmpty
    window.tabs.append(tab)
    if firstTab {
      controller.didOpenWindow(window)
    }
    controller.didOpenTab(tab)
    activate(tab)
  }

  /// The page is gone.
  func detach(_ webView: WKWebView) {
    guard let tab = tabs.removeValue(forKey: ObjectIdentifier(webView)) else { return }
    let wasActive = window.activeTab === tab
    window.tabs.removeAll { $0 === tab }
    if wasActive {
      window.activeTab = nil
      controller.didDeselectTabs([tab])
    }
    controller.didCloseTab(tab, windowIsClosing: window.tabs.isEmpty)
    if window.tabs.isEmpty {
      controller.didCloseWindow(window)
    } else if wasActive, let last = window.tabs.last {
      activate(last)
    }
  }

  /// The page showed again, over the others.
  func activate(_ webView: WKWebView) {
    if let tab = tabs[ObjectIdentifier(webView)] {
      activate(tab)
    }
  }

  /// The page's address, title or loading state changed.
  func pageChanged(_ webView: WKWebView, _ properties: WKWebExtension.TabChangedProperties) {
    if let tab = tabs[ObjectIdentifier(webView)] {
      controller.didChangeTabProperties(properties, for: tab)
    }
  }

  private func activate(_ tab: HostTab) {
    guard window.activeTab !== tab else { return }
    let previous = window.activeTab
    window.activeTab = tab
    if let previous {
      controller.didDeselectTabs([previous])
    }
    controller.didActivateTab(tab, previousActiveTab: previous)
    controller.didSelectTabs([tab])
    controller.didFocusWindow(window)
  }
}

extension WebExtensionRuntime: WKWebExtensionControllerDelegate {
  func webExtensionController(_: WKWebExtensionController, openWindowsFor _: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
    window.tabs.isEmpty ? [] : [window]
  }

  func webExtensionController(_: WKWebExtensionController, focusedWindowFor _: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
    window.tabs.isEmpty ? nil : window
  }

  func webExtensionController(_: WKWebExtensionController, promptForPermissions permissions: Set<WKWebExtension.Permission>, in _: (any WKWebExtensionTab)?, for _: WKWebExtensionContext, completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void) {
    completionHandler(permissions, nil)
  }

  func webExtensionController(_: WKWebExtensionController, promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>, in _: (any WKWebExtensionTab)?, for _: WKWebExtensionContext, completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void) {
    completionHandler(matchPatterns, nil)
  }

  func webExtensionController(_: WKWebExtensionController, promptForPermissionToAccess urls: Set<URL>, in _: (any WKWebExtensionTab)?, for _: WKWebExtensionContext, completionHandler: @escaping (Set<URL>, Date?) -> Void) {
    completionHandler(urls, nil)
  }
}

/// A page shown in the app, as extensions see it: a browser tab.
@MainActor
private final class HostTab: NSObject, WKWebExtensionTab {
  weak var webView: WKWebView?
  weak var window: HostWindow?

  init(webView: WKWebView, window: HostWindow) {
    self.webView = webView
    self.window = window
  }

  func window(for _: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
    window
  }

  func indexInWindow(for _: WKWebExtensionContext) -> Int {
    window?.tabs.firstIndex { $0 === self } ?? NSNotFound
  }

  func webView(for _: WKWebExtensionContext) -> WKWebView? {
    webView
  }

  func title(for _: WKWebExtensionContext) -> String? {
    webView?.title
  }

  func url(for _: WKWebExtensionContext) -> URL? {
    webView?.url
  }

  func isSelected(for _: WKWebExtensionContext) -> Bool {
    window?.activeTab === self
  }

  func isLoadingComplete(for _: WKWebExtensionContext) -> Bool {
    webView?.isLoading == false
  }

  func size(for _: WKWebExtensionContext) -> CGSize {
    webView?.bounds.size ?? .zero
  }
}

/// The app's window, as extensions see it: one window holding every page shown.
@MainActor
private final class HostWindow: NSObject, WKWebExtensionWindow {
  var tabs: [HostTab] = []
  weak var activeTab: HostTab?

  func tabs(for _: WKWebExtensionContext) -> [any WKWebExtensionTab] {
    tabs
  }

  func activeTab(for _: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
    activeTab
  }

  func windowType(for _: WKWebExtensionContext) -> WKWebExtension.WindowType {
    .normal
  }

  func windowState(for _: WKWebExtensionContext) -> WKWebExtension.WindowState {
    .normal
  }

  /// Not private browsing: WebKit runs no extension in a page whose data store keeps nothing
  /// on disk, so pages use one that's cleared at launch instead (`WebPageStorage`).
  func isPrivate(for _: WKWebExtensionContext) -> Bool {
    false
  }

  func frame(for _: WKWebExtensionContext) -> CGRect {
    tabs.lazy.compactMap { $0.webView?.window?.frame }.first ?? .null
  }

  func screenFrame(for _: WKWebExtensionContext) -> CGRect {
    tabs.lazy.compactMap { $0.webView?.window?.windowScene?.screen.bounds }.first ?? .null
  }
}
