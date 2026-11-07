//
//  MacUpdater.swift
//  Helio
//

#if targetEnvironment(macCatalyst)
  import Foundation
  import Observation
  import os

  /// Sparkle updates for the Mac app, through the macOS plugin `HelioMacUpdater.bundle`
  /// (Sources/HelioMacUpdater, built by App/HelioMacUpdater): Sparkle is AppKit, which a Mac
  /// Catalyst app can't link, so the plugin is loaded at runtime and called through the
  /// Objective-C runtime.
  ///
  /// The checks go to the appcast on GitHub Pages and the update itself to GitHub Releases, and
  /// only once the user allows them: Sparkle asks on the second launch, and Settings can turn
  /// them off.
  @MainActor
  @Observable
  final class MacUpdater {
    static let shared = MacUpdater()

    private static let logger = Logger(subsystem: "com.sertacozercan.helio", category: "Updater")
    private static let automaticallyChecksKey = "automaticallyChecksForUpdates"
    /// The plugin's updater, not started until `start()`. Nil when the bundle is missing or the
    /// app has no update key, which Sparkle needs to trust an ad-hoc signed update; then
    /// there's no menu item or setting.
    @ObservationIgnored private let updater: NSObject?
    @ObservationIgnored private var started = false
    /// Sparkle's setting as last read. Sparkle's own prompt changes it too, so it's read again
    /// whenever the app's user defaults change, where Sparkle keeps it.
    private var checksAutomatically = false
    /// False while Sparkle downloads the feed or an update in the background, when a check
    /// does nothing.
    private(set) var canCheckForUpdates = false

    var isAvailable: Bool {
      updater != nil
    }

    var automaticallyChecks: Bool {
      get { checksAutomatically }
      set {
        updater?.setValue(newValue, forKey: Self.automaticallyChecksKey)
        refresh()
      }
    }

    private init() {
      updater = Self.loadUpdater()
      guard updater != nil else { return }
      refresh()
      observeCanCheckForUpdates()
      // The singleton lives as long as the app, so the observer is never removed.
      NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.refresh() }
      }
    }

    private func observeCanCheckForUpdates() {
      guard let updater else { return }
      let observe = NSSelectorFromString("observeCanCheckForUpdates:")
      let handler: @convention(block) (Bool) -> Void = { [weak self] canCheck in
        Task { @MainActor in self?.canCheckForUpdates = canCheck }
      }
      typealias Observe = @convention(c) (AnyObject, Selector, @convention(block) (Bool) -> Void) -> Void
      unsafeBitCast(updater.method(for: observe), to: Observe.self)(updater, observe, handler)
    }

    private func refresh() {
      let value = (updater?.value(forKey: Self.automaticallyChecksKey) as? Bool) ?? false
      if value != checksAutomatically {
        checksAutomatically = value
      }
    }

    /// Starts Sparkle's schedule, once. Call it after the first window shows: Sparkle's prompt
    /// opens right away, and one opened before the window ends up behind it.
    func start() {
      guard !started, let updater else { return }
      started = true
      let start = NSSelectorFromString("start")
      // `start` returns an Objective-C BOOL, which `perform` can't return; call it directly.
      typealias Start = @convention(c) (AnyObject, Selector) -> Bool
      if !unsafeBitCast(updater.method(for: start), to: Start.self)(updater, start) {
        Self.logger.error("The updater didn't start")
      }
    }

    func checkForUpdates() {
      start()
      _ = updater?.perform(NSSelectorFromString("checkForUpdates"))
    }

    private static func loadUpdater() -> NSObject? {
      guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, !key.isEmpty else {
        logger.info("No SUPublicEDKey in Info.plist; updates are off")
        return nil
      }
      guard let url = Bundle.main.builtInPlugInsURL?.appendingPathComponent("HelioMacUpdater.bundle"),
            let bundle = Bundle(url: url)
      else {
        logger.error("No updater plugin in the app")
        return nil
      }
      do {
        try bundle.loadAndReturnError()
      } catch {
        logger.error("Couldn't load the updater plugin: \(error.localizedDescription, privacy: .public)")
        return nil
      }
      guard let updaterClass = bundle.principalClass as? NSObject.Type else {
        logger.error("The updater plugin has no principal class")
        return nil
      }
      let updater = updaterClass.init()
      for name in ["start", "checkForUpdates", "observeCanCheckForUpdates:", "automaticallyChecksForUpdates"] where !updater.responds(to: NSSelectorFromString(name)) {
        logger.error("The updater plugin has no \(name, privacy: .public)")
        return nil
      }
      return updater
    }
  }
#endif
