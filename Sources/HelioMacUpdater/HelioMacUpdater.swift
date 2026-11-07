//
//  HelioMacUpdater.swift
//  Helio
//
//  Sparkle updates for the Mac app. Sparkle is AppKit, which a Mac Catalyst app can't link, so
//  App/HelioMacUpdater builds this into a macOS plugin bundle that HelioKit's MacUpdater loads
//  at runtime and calls through the Objective-C runtime. Keep the @objc names below in sync
//  with MacUpdater.
//

#if os(macOS)
  import Foundation
  import os
  import Sparkle

  private let logger = Logger(subsystem: "com.sertacozercan.helio", category: "Updater")

  /// The plugin's principal class: Sparkle's standard updater and its windows.
  @MainActor
  @objc(HelioMacUpdater)
  public final class HelioMacUpdater: NSObject {
    private let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    private var canCheckObservation: NSKeyValueObservation?

    /// Starts the updater, which checks on its own schedule once the user allows it: Sparkle
    /// asks on the second launch.
    @objc public func start() -> Bool {
      do {
        try controller.updater.start()
        return true
      } catch {
        logger.error("Sparkle didn't start: \(error.localizedDescription, privacy: .public)")
        return false
      }
    }

    /// Checks now, showing Sparkle's progress, update and up-to-date windows.
    @objc public func checkForUpdates() {
      controller.checkForUpdates(nil)
    }

    /// Calls `handler` with whether a check can start now, and again each time that changes. It
    /// can't while Sparkle downloads the feed or an update in the background, and then
    /// `checkForUpdates()` does nothing.
    @objc public func observeCanCheckForUpdates(_ handler: @escaping (Bool) -> Void) {
      canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { updater, _ in
        handler(updater.canCheckForUpdates)
      }
    }

    /// Whether Sparkle checks on its own, once a day by default.
    @objc public var automaticallyChecksForUpdates: Bool {
      get { controller.updater.automaticallyChecksForUpdates }
      set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
  }
#endif
