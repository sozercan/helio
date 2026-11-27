import Foundation

enum Simulator {
  static let name = "Helio Perf"

  static func boot() -> String {
    let udid = ProcessInfo.processInfo.environment["HELIO_PERF_SIMULATOR"] ?? existing() ?? create()
    shell(["xcrun", "simctl", "boot", udid], check: false)
    shell(["xcrun", "simctl", "bootstatus", udid, "-b"])
    return udid
  }

  private static func existing() -> String? {
    let devices = json(shell(["xcrun", "simctl", "list", "devices", "available", "--json"]).output)["devices"] as? [String: [[String: Any]]] ?? [:]
    return devices.filter { $0.key.contains("iOS") }.values.joined().first { $0["name"] as? String == name }?["udid"] as? String
  }

  private static func create() -> String {
    if let udid = createOnNewestRuntime() {
      return udid
    }
    print("no iOS 26+ simulator runtime installed; downloading it")
    shell(["xcodebuild", "-downloadPlatform", "iOS"])
    guard let udid = createOnNewestRuntime() else { fail("no iOS 26+ simulator runtime available") }
    return udid
  }

  private static func createOnNewestRuntime() -> String? {
    let runtimes = json(shell(["xcrun", "simctl", "list", "runtimes", "available", "--json"]).output)["runtimes"] as? [[String: Any]] ?? []
    func version(_ runtime: [String: Any]) -> [Int] {
      ((runtime["version"] as? String) ?? "0").split(separator: ".").compactMap { Int($0) }
    }
    func isGeneral(_ runtime: [String: Any]) -> Bool {
      ((runtime["identifier"] as? String) ?? "").range(of: #"SimRuntime\.iOS-[0-9-]+$"#, options: .regularExpression) != nil
    }
    let ios = runtimes
      .filter { $0["platform"] as? String == "iOS" && (version($0).first ?? 0) >= 26 }
      .sorted { a, b in
        isGeneral(a) == isGeneral(b) ? version(a).lexicographicallyPrecedes(version(b)) : !isGeneral(a)
      }
    for runtime in ios.reversed() {
      guard let runtimeID = runtime["identifier"] as? String else { continue }
      let iPhones = (runtime["supportedDeviceTypes"] as? [[String: Any]] ?? [])
        .filter { $0["productFamily"] as? String == "iPhone" && !(($0["name"] as? String) ?? "").contains("Duo") }
        .compactMap { $0["identifier"] as? String }
      guard let deviceType = iPhones.first(where: { $0.hasSuffix(".iPhone-17") }) ?? iPhones.last else { continue }
      return shell(["xcrun", "simctl", "create", name, deviceType, runtimeID]).output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return nil
  }
}
