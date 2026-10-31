import Foundation

enum Paths {
  /// The checkout this tool belongs to: this file is `Tools/perf/Sources/perf/Shell.swift`.
  static let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  static let tool = repo.appendingPathComponent("Tools/perf")
  static let work = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HELIO_PERF_DIR"]
    ?? NSTemporaryDirectory().appending("helio-perf"))

  static func label(_ label: String) -> URL {
    work.appendingPathComponent(label)
  }
}

struct CommandResult {
  let status: Int32
  let output: String
}

/// Runs a command. With `log`, output goes to that file instead of being captured. With `check`,
/// a failure ends the tool and shows the end of the output.
@discardableResult
func shell(_ arguments: [String], env: [String: String] = [:], log: URL? = nil, check: Bool = true) -> CommandResult {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = arguments
  process.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
  let pipe = Pipe()
  var handle: FileHandle?
  if let log {
    FileManager.default.createFile(atPath: log.path, contents: nil)
    handle = try? FileHandle(forWritingTo: log)
    process.standardOutput = handle
    process.standardError = handle
  } else {
    process.standardOutput = pipe
    process.standardError = pipe
  }
  do {
    try process.run()
  } catch {
    fail("can't run \(arguments.joined(separator: " ")): \(error)")
  }
  let data = log == nil ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
  process.waitUntilExit()
  try? handle?.close()
  let output = log.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? String(decoding: data, as: UTF8.self)
  if check, process.terminationStatus != 0 {
    fail("\(arguments.prefix(3).joined(separator: " ")) failed:\n\(output.suffix(3000))")
  }
  return CommandResult(status: process.terminationStatus, output: output)
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("error: \(message)\n".utf8))
  exit(1)
}

func modificationDate(_ url: URL) -> Date? {
  (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
}

func json(_ text: String) -> [String: Any] {
  (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
}
