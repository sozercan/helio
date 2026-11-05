import Foundation
import Testing
@testable import HelioKit

@MainActor
struct WebExtensionStoreTests {
  private let root = FileManager.default.temporaryDirectory.appending(path: "WebExtensionStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)

  /// An extension folder with `manifest` and, optionally, its English messages.
  private func extensionFolder(_ manifest: [String: Any], messages: [String: Any]? = nil) throws -> URL {
    let folder = root.appending(path: "source-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appending(path: "manifest.json"))
    if let messages {
      let locale = folder.appending(path: "_locales/en", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: locale, withIntermediateDirectories: true)
      try JSONSerialization.data(withJSONObject: messages).write(to: locale.appending(path: "messages.json"))
    }
    return folder
  }

  @Test func addingCopiesTheFolderAndKeepsTheList() throws {
    let store = WebExtensionStore(directory: root.appending(path: "store"))
    let source = try extensionFolder(["name": "Blocker", "version": "1.2", "manifest_version": 3])
    let ext = try store.add(from: source)

    #expect(ext.name == "Blocker")
    #expect(ext.version == "1.2")
    #expect(ext.isEnabled)
    #expect(store.changedSinceLaunch)
    // A copy: the original can go.
    try FileManager.default.removeItem(at: source)
    #expect(store.enabledFolders.map(\.id) == [ext.id])

    let reopened = WebExtensionStore(directory: root.appending(path: "store"))
    #expect(reopened.extensions == [ext])
    #expect(!reopened.changedSinceLaunch)
  }

  @Test func aFolderWithoutAManifestIsRefused() throws {
    let store = WebExtensionStore(directory: root.appending(path: "store"))
    let empty = root.appending(path: "empty", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
    #expect(throws: WebExtensionStoreError.self) { try store.add(from: empty) }
    #expect(store.extensions.isEmpty)
  }

  @Test func aDisabledOrRemovedExtensionDoesntLoad() throws {
    let store = WebExtensionStore(directory: root.appending(path: "store"))
    let ext = try store.add(from: extensionFolder(["name": "Blocker"]))
    try store.setEnabled(false, for: ext)
    #expect(store.enabledFolders.isEmpty)
    try store.setEnabled(true, for: ext)
    #expect(store.enabledFolders.count == 1)

    try store.remove(ext)
    #expect(store.extensions.isEmpty)
    // Its files stay while it may be running, until the next launch.
    #expect(FileManager.default.fileExists(atPath: store.folder(of: ext).path))
    _ = WebExtensionStore(directory: store.directory)
    #expect(!FileManager.default.fileExists(atPath: store.folder(of: ext).path))
  }

  @Test func aChangeThatCantBeSavedIsntMade() throws {
    let store = WebExtensionStore(directory: root.appending(path: "store"))
    let ext = try store.add(from: extensionFolder(["name": "Blocker"]))
    // The list can't be written where a folder stands in for it.
    let list = store.directory.appending(path: "extensions.json")
    try FileManager.default.removeItem(at: list)
    try FileManager.default.createDirectory(at: list, withIntermediateDirectories: true)

    #expect(throws: (any Error).self) { try store.setEnabled(false, for: ext) }
    #expect(store.extensions.first?.isEnabled == true)
    #expect(throws: (any Error).self) { try store.add(from: extensionFolder(["name": "Other"])) }
    #expect(store.extensions.count == 1)
    #expect(throws: (any Error).self) { try store.remove(ext) }
    #expect(store.extensions == [ext])
  }

  @Test func aLocalizedNameComesFromTheDefaultLocale() throws {
    let folder = try extensionFolder(["name": "__MSG_extName__", "default_locale": "en"], messages: ["extName": ["message": "uBlock Origin Lite"]])
    #expect(WebExtensionStore.displayName(manifest: ["name": "__MSG_extName__", "default_locale": "en"], folder: folder) == "uBlock Origin Lite")
    // A message it can't find: the folder's name.
    #expect(WebExtensionStore.displayName(manifest: ["name": "__MSG_missing__"], folder: folder) == folder.lastPathComponent)
  }
}
