#if os(macOS)
  import Foundation
  import os
  import Sparkle

  private let logger = Logger(subsystem: "com.sertacozercan.helio", category: "Updater")

  @MainActor
  @objc(HelioMacUpdater)
  public final class HelioMacUpdater: NSObject {
    private let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    private var canCheckObservation: NSKeyValueObservation?

    @objc public func start() -> Bool {
      do {
        try controller.updater.start()
        return true
      } catch {
        logger.error("Sparkle didn't start: \(error.localizedDescription, privacy: .public)")
        return false
      }
    }

    @objc public func checkForUpdates() {
      controller.checkForUpdates(nil)
    }

    @objc public func observeCanCheckForUpdates(_ handler: @escaping (Bool) -> Void) {
      canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { updater, _ in
        handler(updater.canCheckForUpdates)
      }
    }

    @objc public var automaticallyChecksForUpdates: Bool {
      get { controller.updater.automaticallyChecksForUpdates }
      set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
  }
#endif
