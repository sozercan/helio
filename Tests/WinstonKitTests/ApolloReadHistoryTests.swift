import Foundation
import Testing
import Zip
@testable import WinstonKit

struct ApolloReadHistoryTests {
  private func preferences(_ dictionary: [String: Any]) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
  }

  @Test func normalizesPostIDs() {
    #expect(ApolloReadHistory.postID("t3_AbC123") == "abc123")
    #expect(ApolloReadHistory.postID(" 1x2y3z\n") == "1x2y3z")
    #expect(ApolloReadHistory.postID("") == nil)
    #expect(ApolloReadHistory.postID("t3_") == nil)
    #expect(ApolloReadHistory.postID("abc-123") == nil)
    #expect(ApolloReadHistory.postID("ábc") == nil)
  }

  @Test func readsUniqueIDsFromPreferences() throws {
    let data = try preferences(["ReadPostIDs": ["abc", "t3_def", "ABC", "not valid", "ghi"], "Other": 1])
    let parsed = try ApolloReadHistory.postIDs(inPreferences: data)
    #expect(parsed.ids == ["abc", "def", "ghi"])
    #expect(parsed.invalid == 1)
  }

  @Test func rejectsPreferencesWithoutReadHistory() throws {
    #expect(throws: ApolloReadHistoryImportError.missingReadPostIDs) {
      try ApolloReadHistory.postIDs(inPreferences: try preferences(["Other": 1]))
    }
    #expect(throws: ApolloReadHistoryImportError.unreadablePreferences) {
      try ApolloReadHistory.postIDs(inPreferences: Data("not a plist".utf8))
    }
  }

  @Test func findsPreferencesInsideABackupZip() throws {
    let fileManager = FileManager.default
    let dir = fileManager.temporaryDirectory.appendingPathComponent("apollo-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: dir) }
    let backup = dir.appendingPathComponent("Apollo Backup", isDirectory: true)
    try fileManager.createDirectory(at: backup, withIntermediateDirectories: true)
    try preferences(["ReadPostIDs": ["abc", "def"]]).write(to: backup.appendingPathComponent("preferences.plist"))
    let zip = dir.appendingPathComponent("backup.zip")
    try Zip.zipFiles(paths: [backup], zipFilePath: zip, password: nil, progress: nil)

    let parsed = try ApolloReadHistory.postIDs(inBackupAt: zip)
    #expect(parsed.ids == ["abc", "def"])
  }

  @Test func rejectsOtherFileTypes() {
    #expect(throws: ApolloReadHistoryImportError.unsupportedFile) {
      try ApolloReadHistory.postIDs(inBackupAt: URL(fileURLWithPath: "/tmp/backup.json"))
    }
  }
}
