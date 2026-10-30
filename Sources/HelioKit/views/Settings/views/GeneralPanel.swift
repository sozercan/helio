//
//  GeneralPanel.swift
//  Helio
//
//  Created by Daniel Inama on 17/08/23.
//

import Defaults
import Nuke
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct GeneralPanel: View {
  @Default(.likedButNotSubbed) var likedButNotSubbed
  @Default(.BehaviorDefSettings) var behaviorDefSettings
  @Default(.GeneralDefSettings) var generalDefSettings
  @State private var totalCacheSize: String = ""
  @Environment(\.useTheme) private var theme
  @State var isMoving: Bool = false
  @State var settingsFileURL: String = ""
  @State var doImport: Bool = false
  @State private var importKind: ImportKind = .settings
  @State private var importingApolloReadHistory = false
  @State private var apolloImportMessage: String?

  enum ImportKind { case settings, apolloReadHistory }
  @State private var showClearReadHistoryAlert = false
  var body: some View {
    List {
      Group {
        Section {
          Toggle("Sync credentials", systemImage: "person.2.badge.key.fill", isOn: $behaviorDefSettings.iCloudSyncCredentials)
          //          Toggle("Sync preferences", systemImage: "slider.horizontal.3", isOn: $generalDefSettings.iCloudSyncUserDefaults)
          //            .onChange(of: generalDefSettings.iCloudSyncUserDefaults) { _, new in
          //              Zephyr.syncUbiquitousKeyValueStoreOnChange = new
          //            }
          //          WListButton {
          //            print(NSUbiquitousKeyValueStore.default.dictionaryRepresentation["ZephyrSyncKey"])
          //            print(UserDefaults.standard.dictionaryRepresentation()["ZephyrSyncKey"])
          ////            Zephyr.sync()
          //          } label: {
          //            Label("Force preferences sync", systemImage: "arrow.clockwise")
          //          }
        } header: {
          Text("iCloud")
        }
        //      footer: {
        //          Text("Syncing will run on every app restart and on every preference change. Preferences also include themes.")
        //        }

        Section("Backup") {
          WListButton {
            let date = Date()
            let file = exportUserDefaultsToJSON(fileName: "HelioSettings-" + date.ISO8601Format() + ".json")
            if let file {
              isMoving.toggle()
              settingsFileURL = file
            }
          } label: {
            Label("Export Settings", systemImage: "arrowshape.turn.up.left")
          }
          .fileMover(isPresented: $isMoving, file: URL(string: settingsFileURL), onCompletion: { _ in
            //          print(completion)
          })

          WListButton {
            importKind = .settings
            doImport.toggle()
          } label: {
            Label("Import Settings", systemImage: "square.and.arrow.down")
          }

          WListButton {
            importKind = .apolloReadHistory
            doImport.toggle()
          } label: {
            HStack {
              Label("Import Apollo read history", systemImage: "eye")
              if importingApolloReadHistory {
                Spacer()
                ProgressView()
              }
            }
          }
          .disabled(importingApolloReadHistory)
        }
        // One importer for both buttons: sibling .fileImporter modifiers can shadow each other.
        .fileImporter(isPresented: $doImport, allowedContentTypes: importKind == .apolloReadHistory ? [.zip, .propertyList] : [UTType.json], allowsMultipleSelection: false, onCompletion: { result in
          switch (importKind, result) {
          case let (.settings, .success(file)):
            let success = importUserDefaultsFromJSON(jsonFilePath: file[0])
            if success {
              print("success")
            } else {
              print("error")
            }
          case let (.apolloReadHistory, .success(files)):
            if let file = files.first {
              importApolloReadHistory(file)
            }
          case let (_, .failure(error)):
            print(error.localizedDescription)
          }
        })

        Section("Advanced") {
          WListButton {
            resetPreferences()
          } label: {
            Label("Reset preferences", systemImage: "trash")
              .foregroundColor(.red)
          }

          WListButton {
            clearCache()
            resetCaches()
          } label: {
            Label("Clear Cache (" + totalCacheSize + ")", systemImage: "trash")
              .foregroundColor(.red)
          }
          .task {
            await calculateTotalCacheSize()
          }

          WListButton {
            showClearReadHistoryAlert = true
          } label: {
            Label("Clear read history", systemImage: "eye.slash")
              .foregroundColor(.red)
          }

          WListButton {
            likedButNotSubbed = []
          } label: {
            Label("Clear " + String(likedButNotSubbed.count) + " Local Favorites", systemImage: "heart.slash.fill")
              .foregroundColor(.red)
          }
        }
      }
      .themedListSection()
    }
    .themedListBG(theme.lists.bg)
    .alert("Apollo read history", isPresented: Binding(get: { apolloImportMessage != nil }, set: {
      if !$0 {
        apolloImportMessage = nil
      }
    })) {
      Button("OK") {}
    } message: {
      Text(apolloImportMessage ?? "")
    }
    .alert("Clear read history?", isPresented: $showClearReadHistoryAlert) {
      Button("Clear", role: .destructive) { clearReadHistory() }
    } message: {
      Text("Every post will show as unread again. Reload feeds to update posts already on screen.")
    }
    .navigationTitle("General")
    .navigationBarTitleDisplayMode(.inline)
  }

  func importApolloReadHistory(_ file: URL) {
    importingApolloReadHistory = true
    Task {
      let message: String
      do {
        let result = try await ApolloReadHistory.importBackup(at: file)
        message = "Marked \(result.imported) posts as read (\(result.found - result.imported) already were). Reload feeds to update posts already on screen."
      } catch {
        message = error.localizedDescription
      }
      await MainActor.run {
        importingApolloReadHistory = false
        apolloImportMessage = message
      }
    }
  }

  /// Sizes the cache off the main thread: walking a large cache would otherwise hang the app.
  func calculateTotalCacheSize() async {
    let totalSize = await Task.detached(priority: .utility) {
      appCacheDirectories().reduce(0) { $0 + Self.calculateDirectorySize(directory: $1) }
    }.value
    totalCacheSize = ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
  }

  static func calculateDirectorySize(directory: URL?) -> Int {
    guard let directory else {
      return 0
    }

    let fileManager = FileManager.default
    var totalSize = 0

    if let fileURLs = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: [], errorHandler: nil) {
      for case let fileURL as URL in fileURLs {
        do {
          let resourceValues = try fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
          if let fileSize = resourceValues.totalFileAllocatedSize {
            totalSize += fileSize
          }
        } catch {
          print("Error calculating file size: \(error.localizedDescription)")
        }
      }
    }

    return totalSize
  }

  func clearCache() {
    do {
      // Attempt to flush the custom data cache
      let dataCache = try DataCache(name: imageDataCacheName)
      try dataCache.flush()
      print("Custom DataCache flushed successfully.")
    } catch {
      print("Failed to flush DataCache with error: \(error)")
    }

    // Clearing Nuke's image and data caches
    Nuke.ImageCache.shared.removeAll()
    print("Nuke ImageCache cleared.")

    Nuke.DataLoader.sharedUrlCache.removeAllCachedResponses()
    print("Nuke DataLoader cache cleared.")

    // Try to clear URL session configuration cache
    URLCache.shared.removeAllCachedResponses()

    appCacheDirectories().forEach(flushFilesInDirectoryButNotFolders)

    // Resetting Core Data, except read history
    resetCoreData(keeping: ["SeenPost"])

    totalCacheSize = "0 bytes"
    print("Cache cleared successfully.")
  }

  func clearDirectory(directory: URL?) {
    guard let directory else {
      return
    }

    let fileManager = FileManager.default

    do {
      let fileURLs = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)

      for fileURL in fileURLs {
        try fileManager.removeItem(at: fileURL)
      }
    } catch {
      print("Error deleting files in directory: \(error.localizedDescription)")
    }
  }
}

/// The directories holding only this app's cache files. On iOS, and in a sandboxed Mac app, the
/// caches and temporary directories belong to the app. An unsandboxed Mac app shares them with
/// every other app, so only the folders named after it are its own: sizing all of them hung the
/// app, and clearing them deleted other apps' caches.
func appCacheDirectories() -> [URL] {
  let fileManager = FileManager.default
  guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return [] }
  #if targetEnvironment(macCatalyst)
    if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil {
      return [Bundle.main.bundleIdentifier, imageDataCacheName]
        .compactMap(\.self)
        .map { caches.appendingPathComponent($0, isDirectory: true) }
        .filter { fileManager.fileExists(atPath: $0.path) }
    }
  #endif
  return [fileManager.temporaryDirectory, caches]
}

func flushFilesInDirectoryButNotFolders(_ at: URL?) {
  guard let directoryURL = at else { return }
  let fileManager = FileManager.default

  guard let enumerator = fileManager.enumerator(at: directoryURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles], errorHandler: { url, error -> Bool in
    print("Enumerator error at \(url): \(error). Skipping...")
    return true
  }) else { return }

  for case let fileURL as URL in enumerator {
    do {
      // Check if the file or directory is part of the Nuke cache or related to SQLite (which crashes if related file is currently in use by the app)
      let path = fileURL.path
      if path.contains("com.github.kean.Nuke.Cache") || path.contains("sqlite") || path.hasSuffix(".db")
        || path.hasSuffix("-journal") || path.hasSuffix("-wal") || path.hasSuffix("-shm")
      {
        // Skip this file or directory
        continue
      }

      let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
      if let isDirectory = resourceValues.isDirectory, !isDirectory {
        try fileManager.removeItem(at: fileURL)
        print("Removed item at \(path)")
      }
    } catch {
      print("Error removing item at \(fileURL.path): \(error)")
    }
  }
}
