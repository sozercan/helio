import CoreData
import Nuke
import SwiftUI
import WhatsNewKit

let imageDataCacheName = "com.sertacozercan.helio.datacache"

public struct HelioScene: Scene {
  let persistenceController = PersistenceController.shared

  public init() {}

  public var body: some Scene {
    WindowGroup {
      AppContent()
        .trackContentTextScale()
        .environment(\.managedObjectContext, persistenceController.container.viewContext)
        .environment(\.primaryBGContext, persistenceController.primaryBGContext)
        .environment(
          \.whatsNew,
          WhatsNewEnvironment(currentVersion: .current(), whatsNewCollection: getCurrentChangelog()),
        )
        .task {
          ImagePipeline.shared = ImagePipeline(configuration: .withDataCache(name: imageDataCacheName, sizeLimit: 1024 * 1024 * 300))
        }
      #if targetEnvironment(macCatalyst)
        .task { MacUpdater.shared.start() }
      #endif
    }
    .commands { NavCommands() }
  }
}
