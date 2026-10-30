//
//  importApolloReadHistory.swift
//  Helio
//
//  Imports the read posts stored in an Apollo backup (`ReadPostIDs` in preferences.plist).
//

import CoreData
import Foundation
import Zip

enum ApolloReadHistoryImportError: LocalizedError {
  case unsupportedFile
  case preferencesNotFound
  case unreadablePreferences
  case missingReadPostIDs

  var errorDescription: String? {
    switch self {
    case .unsupportedFile: "Choose an Apollo backup .zip or its preferences.plist."
    case .preferencesNotFound: "This backup doesn't contain preferences.plist."
    case .unreadablePreferences: "Apollo's preferences.plist couldn't be read."
    case .missingReadPostIDs: "This backup has no read history."
    }
  }
}

enum ApolloReadHistory {
  struct ImportResult: Equatable {
    var found: Int
    var imported: Int
    var invalid: Int
  }

  /// Reads Apollo's read post ids from a backup .zip or preferences.plist and marks them read.
  static func importBackup(at url: URL) async throws -> ImportResult {
    let parsed = try postIDs(inBackupAt: url)
    let imported = try await markRead(postIDs: parsed.ids)
    return ImportResult(found: parsed.ids.count, imported: imported, invalid: parsed.invalid)
  }

  static func postIDs(inBackupAt url: URL) throws -> (ids: [String], invalid: Int) {
    let didAccess = url.startAccessingSecurityScopedResource()
    defer {
      if didAccess {
        url.stopAccessingSecurityScopedResource()
      }
    }

    switch url.pathExtension.lowercased() {
    case "plist":
      return try postIDs(inPreferences: Data(contentsOf: url))
    case "zip":
      let fileManager = FileManager.default
      let workDir = fileManager.temporaryDirectory.appendingPathComponent("apollo-import-\(UUID().uuidString)", isDirectory: true)
      defer { try? fileManager.removeItem(at: workDir) }
      try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)
      // Zip needs a path it can read after the security scope ends.
      let zipCopy = workDir.appendingPathComponent("backup.zip")
      try fileManager.copyItem(at: url, to: zipCopy)
      let unzipped = workDir.appendingPathComponent("unzipped", isDirectory: true)
      try Zip.unzipFile(zipCopy, destination: unzipped, overwrite: true, password: nil)
      let files = fileManager.enumerator(at: unzipped, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
      guard let preferences = files.first(where: { $0.lastPathComponent == "preferences.plist" }) else {
        throw ApolloReadHistoryImportError.preferencesNotFound
      }
      return try postIDs(inPreferences: Data(contentsOf: preferences))
    default:
      throw ApolloReadHistoryImportError.unsupportedFile
    }
  }

  static func postIDs(inPreferences data: Data) throws -> (ids: [String], invalid: Int) {
    guard let preferences = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
      throw ApolloReadHistoryImportError.unreadablePreferences
    }
    guard let rawIDs = preferences["ReadPostIDs"] as? [String] else {
      throw ApolloReadHistoryImportError.missingReadPostIDs
    }
    var seen = Set<String>()
    var ids: [String] = []
    var invalid = 0
    for rawID in rawIDs {
      guard let id = postID(rawID) else { invalid += 1
        continue
      }
      if seen.insert(id).inserted {
        ids.append(id)
      }
    }
    return (ids, invalid)
  }

  /// Bare base-36 post id, without a "t3_" prefix.
  static func postID(_ raw: String) -> String? {
    var id = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if id.hasPrefix("t3_") {
      id.removeFirst(3)
    }
    guard !id.isEmpty, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
    return id
  }

  /// Adds read entries for posts that don't have one. Returns how many were added.
  /// Uses its own context, so a failed import leaves nothing half-inserted in the shared one.
  static func markRead(postIDs ids: [String]) async throws -> Int {
    let context = PersistenceController.shared.container.newBackgroundContext()
    context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    return try await context.perform(schedule: .enqueued) {
      var added = 0
      for start in stride(from: 0, to: ids.count, by: 500) {
        let chunk = Array(ids[start ..< min(start + 500, ids.count)])
        let fetchRequest = NSFetchRequest<SeenPost>(entityName: "SeenPost")
        fetchRequest.predicate = NSPredicate(format: "postID IN %@", chunk)
        let existing = try Set(context.fetch(fetchRequest).compactMap(\.postID))
        for id in chunk where !existing.contains(id) {
          SeenPost(context: context).postID = id
          added += 1
        }
      }
      try context.save()
      return added
    }
  }
}
