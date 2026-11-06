//
//  WebExtensionStore.swift
//  Helio
//
//  The web extensions the user added, for web pages opened in the app.
//

import Foundation
import os

/// A web extension the user added: a copy of its folder in the app's storage.
struct ManagedWebExtension: Codable, Identifiable, Equatable {
  /// Also the name of its folder in the store.
  let id: String
  var name: String
  var version: String?
  var isEnabled: Bool
}

enum WebExtensionStoreError: LocalizedError {
  case noManifest
  case unreadableManifest

  var errorDescription: String? {
    switch self {
    case .noManifest: "The folder has no manifest.json. Choose the folder that contains it."
    case .unreadableManifest: "The extension's manifest.json couldn't be read."
    }
  }
}

/// The web extensions the user added (none by default). Each is a copy of the folder the user
/// chose, so it doesn't depend on that folder staying where it is; the list is kept beside the
/// copies. `WebExtensionRuntime` loads the enabled ones at launch, so changes apply on the next one.
@MainActor
@Observable
final class WebExtensionStore {
  static let shared = WebExtensionStore()

  private(set) var extensions: [ManagedWebExtension]
  /// Whether the list changed since launch, which only the next launch applies.
  private(set) var changedSinceLaunch = false
  /// Holds the extension folders and the list.
  let directory: URL

  @ObservationIgnored private let logger = Logger(subsystem: "com.sertacozercan.helio", category: "WebExtensions")

  init(directory: URL = WebExtensionStore.defaultDirectory) {
    self.directory = directory
    let listURL = directory.appending(path: "extensions.json")
    let saved = try? JSONDecoder().decode([ManagedWebExtension].self, from: Data(contentsOf: listURL))
    extensions = saved ?? []
    // Only with a list read: without one, no folder can be told apart from a removed one.
    if saved != nil {
      deleteRemovedFolders()
    }
  }

  /// Deletes the folders of extensions removed before this launch: WebKit kept the ones it had
  /// loaded running until then, and they still needed their files.
  private func deleteRemovedFolders() {
    let kept = Set(extensions.map(\.id))
    let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
    for folder in folders where (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && !kept.contains(folder.lastPathComponent) {
      try? FileManager.default.removeItem(at: folder)
    }
  }

  /// Under the app's own folder: on Mac, Application Support is shared by every app.
  nonisolated static var defaultDirectory: URL {
    URL.applicationSupportDirectory.appending(path: "Helio/WebExtensions", directoryHint: .isDirectory)
  }

  private var listURL: URL {
    directory.appending(path: "extensions.json")
  }

  func folder(of ext: ManagedWebExtension) -> URL {
    directory.appending(path: ext.id, directoryHint: .isDirectory)
  }

  /// Whether any extension is turned on. Links then open in the app's web pages, which run them,
  /// instead of Safari's view, which doesn't.
  var hasEnabledExtensions: Bool {
    extensions.contains(where: \.isEnabled)
  }

  /// The enabled extensions whose folders are still there, in the order they were added.
  var enabledFolders: [(id: String, url: URL)] {
    extensions.filter(\.isEnabled).compactMap { ext in
      let url = folder(of: ext)
      guard FileManager.default.fileExists(atPath: url.appending(path: "manifest.json").path) else {
        logger.warning("Extension \(ext.name, privacy: .public) is missing its files")
        return nil
      }
      return (ext.id, url)
    }
  }

  /// Copies the extension in `source`, the folder that holds its manifest.json, into the store,
  /// enabled.
  @discardableResult
  func add(from source: URL) throws -> ManagedWebExtension {
    let accessing = source.startAccessingSecurityScopedResource()
    defer {
      if accessing {
        source.stopAccessingSecurityScopedResource()
      }
    }
    let manifestURL = source.appending(path: "manifest.json")
    guard FileManager.default.fileExists(atPath: manifestURL.path) else { throw WebExtensionStoreError.noManifest }
    guard let manifest = try? JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any] else {
      throw WebExtensionStoreError.unreadableManifest
    }

    let id = UUID().uuidString
    let ext = ManagedWebExtension(id: id, name: Self.displayName(manifest: manifest, folder: source), version: manifest["version"] as? String, isEnabled: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: source, to: folder(of: ext))
    do {
      try save(extensions + [ext])
    } catch {
      try? FileManager.default.removeItem(at: folder(of: ext))
      throw error
    }
    logger.info("Added extension \(ext.name, privacy: .public)")
    return ext
  }

  /// Drops it from the list. Its files go at the next launch, as it may be running until then.
  func remove(_ ext: ManagedWebExtension) throws {
    try save(extensions.filter { $0.id != ext.id })
  }

  func setEnabled(_ enabled: Bool, for ext: ManagedWebExtension) throws {
    guard let index = extensions.firstIndex(where: { $0.id == ext.id }), extensions[index].isEnabled != enabled else { return }
    var updated = extensions
    updated[index].isEnabled = enabled
    try save(updated)
  }

  /// Writes `list` and makes it the list, or, when it can't be written, leaves the list as it
  /// was: a change the next launch wouldn't see isn't made.
  private func save(_ list: [ManagedWebExtension]) throws {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try JSONEncoder().encode(list).write(to: listURL, options: .atomic)
    } catch {
      logger.error("Couldn't save the extension list: \(error.localizedDescription, privacy: .public)")
      throw error
    }
    extensions = list
    changedSinceLaunch = true
  }

  /// The manifest's name, looked up in the extension's default locale when it's a message
  /// (`__MSG_extName__`, as in uBlock Origin Lite); else the folder's name.
  static func displayName(manifest: [String: Any], folder: URL) -> String {
    guard let name = manifest["name"] as? String, !name.isEmpty else { return folder.lastPathComponent }
    guard name.hasPrefix("__MSG_"), name.hasSuffix("__") else { return name }
    let key = name.dropFirst("__MSG_".count).dropLast(2).lowercased()
    let locale = manifest["default_locale"] as? String ?? "en"
    let messagesURL = folder.appending(path: "_locales/\(locale)/messages.json")
    guard let messages = try? JSONSerialization.jsonObject(with: Data(contentsOf: messagesURL)) as? [String: Any],
          let entry = messages.first(where: { $0.key.lowercased() == key })?.value as? [String: Any],
          let message = entry["message"] as? String, !message.isEmpty
    else { return folder.lastPathComponent }
    return message
  }
}
