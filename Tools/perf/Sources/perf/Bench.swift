import Foundation

enum Bench {
  static let bundleID = "com.sertacozercan.helio"

  enum Step {
    case wait(Double)
    case mark(String)
    case open(String)
    case scroll(seconds: Double, speed: Double)
  }

  /// Open Home, scroll it through its four pages, open a post, scroll its comments. Navigation and
  /// scrolling run inside the app (see the shim), so no XCUITest accessibility snapshots, which
  /// take a fifth of the main thread, run while measuring.
  static let scenario: [Step] = {
    let feed: [Step] = [.wait(6), .mark("home_open"), .open("helioapp://r/home"), .wait(5), .mark("scroll_start")]
    let feedScrolls: [Step] = (0 ..< 10).flatMap { _ -> [Step] in [.scroll(seconds: 1.2, speed: 3000), .wait(2.2)] }
    let post: [Step] = [.mark("scroll_end"), .wait(3), .mark("post_open"), .open("helioapp://r/pics/comments/pf0001"), .wait(5),
                        .mark("cscroll_start")]
    let commentScrolls: [Step] = (0 ..< 4).flatMap { _ -> [Step] in [.scroll(seconds: 1.0, speed: 2500), .wait(2)] }
    let end: [Step] = [.mark("cscroll_end"), .wait(2), .mark("end"), .wait(1)]
    return feed + feedScrolls + post + commentScrolls + end
  }()

  // MARK: Build

  static func build(label: String, repo: URL, spm: String?) {
    let udid = Simulator.boot()
    let dir = Paths.label(label)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    // Checkouts from before the perf tool lack the setup test: append it to the smoke tests for
    // the build.
    let tests = repo.appendingPathComponent("App/HelioUITests")
    let smoke = tests.appendingPathComponent("SmokeUITests.swift")
    let original = FileManager.default.fileExists(atPath: tests.appendingPathComponent("PerfSetupUITests.swift").path)
      ? nil : try? String(contentsOf: smoke, encoding: .utf8)
    if let original {
      let setup = (try? String(contentsOf: Paths.repo.appendingPathComponent("App/HelioUITests/PerfSetupUITests.swift"), encoding: .utf8)) ?? ""
      try? (original + "\n" + setup.replacingOccurrences(of: "import XCTest\n", with: "")).write(to: smoke, atomically: true, encoding: .utf8)
    }
    defer {
      if let original {
        try? original.write(to: smoke, atomically: true, encoding: .utf8)
      }
    }
    var command = ["xcodebuild", "-project", repo.appendingPathComponent("App/Helio.xcodeproj").path, "-scheme", "Helio",
                   "-configuration", "Release", "-destination", "id=\(udid)", "-derivedDataPath", dir.appendingPathComponent("build").path,
                   "-skipPackagePluginValidation", "build-for-testing"]
    if let spm {
      command += ["-clonedSourcePackagesDirPath", URL(fileURLWithPath: spm).path]
    }
    print("building \(repo.path) as \(label) (log: \(dir.path)/build.log)")
    shell(command, log: dir.appendingPathComponent("build.log"))
    print("built")
  }

  // MARK: Shim

  /// The shim, built for the simulator when missing or older than its source.
  static func shim() -> URL {
    let source = Paths.tool.appendingPathComponent("Shim/HelioPerfShim.swift")
    let out = Paths.work.appendingPathComponent("HelioPerfShim.dylib")
    if let built = modificationDate(out), let edited = modificationDate(source), built > edited {
      return out
    }
    try? FileManager.default.createDirectory(at: Paths.work, withIntermediateDirectories: true)
    let sdk = shell(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
    var system = utsname()
    uname(&system)
    let arch = withUnsafeBytes(of: system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    shell(["xcrun", "--sdk", "iphonesimulator", "swiftc", "-target", "\(arch)-apple-ios26.0-simulator", "-sdk", sdk,
           "-emit-library", "-O", "-swift-version", "5", "-module-name", "HelioPerfShim",
           "-Xlinker", "-init", "-Xlinker", "_helio_perf_init", source.path, "-o", out.path])
    return out
  }

  // MARK: Runs

  static func run(label: String, runs: Int, profile: Bool) {
    let dir = Paths.label(label)
    let products = dir.appendingPathComponent("build/Build/Products")
    guard let xctestrun = (try? FileManager.default.contentsOfDirectory(atPath: products.path))?.first(where: { $0.hasSuffix(".xctestrun") }) else {
      fail("no build for \(label); run: perf build \(label)")
    }
    let udid = Simulator.boot(), shim = shim().path, fixtures = Fixtures.ensure().path
    var complete = 0
    for i in 1 ... runs {
      let log = dir.appendingPathComponent("run\(i).log"), commands = dir.appendingPathComponent("run\(i).cmd")
      let trace = dir.appendingPathComponent("run\(i).trace")
      for stale in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where stale.hasPrefix("run\(i).") {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(stale))
      }
      FileManager.default.createFile(atPath: commands.path, contents: nil)
      shell(["xcrun", "simctl", "terminate", udid, bundleID], check: false)
      shell(["xcrun", "simctl", "uninstall", udid, bundleID], check: false)
      shell(["xcrun", "simctl", "keychain", udid, "reset"], check: false)

      // Install, onboarding and What's New, so the measured launch is a returning user's.
      let setup = shell(["xcodebuild", "test-without-building", "-xctestrun", products.appendingPathComponent(xctestrun).path,
                         "-destination", "id=\(udid)", "-only-testing", "HelioUITests/PerfSetupUITests/testSetup"],
                        env: ["TEST_RUNNER_HELIO_PERF_SHIM": shim, "TEST_RUNNER_HELIO_PERF_FIXTURES": fixtures,
                              "TEST_RUNNER_HELIO_PERF_LOG": log.path + ".setup"],
                        log: dir.appendingPathComponent("run\(i).setup.txt"), check: false)
      guard setup.status == 0 else {
        print("run \(i): setup failed, see \(dir.path)/run\(i).setup.txt")
        continue
      }
      shell(["xcrun", "simctl", "terminate", udid, bundleID], check: false)
      Thread.sleep(forTimeInterval: 1)

      let launched = shell(["xcrun", "simctl", "launch", udid, bundleID],
                           env: ["SIMCTL_CHILD_DYLD_INSERT_LIBRARIES": shim, "SIMCTL_CHILD_PERF_FIXTURES": fixtures,
                                 "SIMCTL_CHILD_PERF_LOG": log.path, "SIMCTL_CHILD_PERF_CMD": commands.path])
      let pid = launched.output.split(separator: " ").last.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
      var recorder: Process?
      if profile {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["xctrace", "record", "--template", "Time Profiler", "--device", udid, "--attach", pid,
                             "--output", trace.path, "--time-limit", "180s"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        recorder = process
      }
      play(scenario, commands: commands)
      if let recorder {
        recorder.interrupt()
        recorder.waitUntilExit()
      }
      shell(["xcrun", "simctl", "terminate", udid, bundleID], check: false)

      let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
      guard RunLog(text: text).marks["end"] != nil else {
        print("run \(i): didn't finish, see \(log.path)")
        continue
      }
      if text.contains(" open_failed") {
        print("run \(i): a deep link didn't open")
      }
      if text.contains(" no_scroll_view") {
        print("run \(i): nothing to scroll when asked (comments not loaded 5 s after opening the post?)")
      }
      if profile, !Profile.export(trace, to: dir.appendingPathComponent("run\(i).tp.xml")) {
        print("run \(i): couldn't export the trace")
      }
      complete += 1
      print("run \(i) ok")
    }
    guard complete > 0 else { fail("no complete runs") }
    Metrics.printSummary(label)
  }

  static func play(_ steps: [Step], commands: URL) {
    var seq = 0
    func send(_ command: String) {
      seq += 1
      guard let handle = try? FileHandle(forWritingTo: commands) else { return }
      handle.seekToEndOfFile()
      handle.write(Data("\(seq) \(command)\n".utf8))
      try? handle.close()
    }
    for step in steps {
      switch step {
      case let .wait(seconds): Thread.sleep(forTimeInterval: seconds)
      case let .mark(name): send("mark \(name)")
      case let .open(url): send("open \(url)")
      case let .scroll(seconds, speed): send("scroll \(seconds) \(speed)")
      }
    }
  }
}
