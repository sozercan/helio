import Foundation
import os

struct ManagedWebExtension: Codable, Identifiable, Equatable {
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

@MainActor
@Observable
final class WebExtensionStore {
  static let shared = WebExtensionStore()

  private(set) var extensions: [ManagedWebExtension]
  private(set) var changedSinceLaunch = false
  let directory: URL

  @ObservationIgnored private let logger = Logger(subsystem: "com.sertacozercan.helio", category: "WebExtensions")

  init(directory: URL = WebExtensionStore.defaultDirectory) {
    self.directory = directory
    let listURL = directory.appending(path: "extensions.json")
    let saved = try? JSONDecoder().decode([ManagedWebExtension].self, from: Data(contentsOf: listURL))
    extensions = saved ?? []
    if saved != nil {
      deleteRemovedFolders()
    }
  }

  private func deleteRemovedFolders() {
    let kept = Set(extensions.map(\.id))
    let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
    for folder in folders where (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && !kept.contains(folder.lastPathComponent) {
      try? FileManager.default.removeItem(at: folder)
    }
  }

  nonisolated static var defaultDirectory: URL {
    URL.applicationSupportDirectory.appending(path: "Helio/WebExtensions", directoryHint: .isDirectory)
  }

  private var listURL: URL {
    directory.appending(path: "extensions.json")
  }

  func folder(of ext: ManagedWebExtension) -> URL {
    directory.appending(path: ext.id, directoryHint: .isDirectory)
  }

  var hasEnabledExtensions: Bool {
    extensions.contains(where: \.isEnabled)
  }

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

  func remove(_ ext: ManagedWebExtension) throws {
    try save(extensions.filter { $0.id != ext.id })
  }

  func setEnabled(_ enabled: Bool, for ext: ManagedWebExtension) throws {
    guard let index = extensions.firstIndex(where: { $0.id == ext.id }), extensions[index].isEnabled != enabled else { return }
    var updated = extensions
    updated[index].isEnabled = enabled
    try save(updated)
  }

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
