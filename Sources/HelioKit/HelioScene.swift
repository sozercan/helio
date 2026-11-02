//
//  HelioScene.swift
//  Helio
//
//  Created by Igor Marcossi on 23/06/23.
//

import CoreData
import Nuke
import SwiftUI
import WhatsNewKit

/// The folder in the caches directory that holds downloaded images.
let imageDataCacheName = "com.sertacozercan.helio.datacache"

/// The app's root scene. The `@main` App lives in the app target, which owns the bundle's
/// resources, and installs `AppDelegate` itself.
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
    }
    .commands { NavCommands() }
  }
}
