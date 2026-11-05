import Foundation

enum Bench {
  static let bundleID = "com.sertacozercan.helio"
  /// The Mac build's own bundle id, so its preferences and saved state never mix with an installed
  /// Helio's, and links to helioapp:// don't open it.
  static let macBundleID = "com.sertacozercan.helio.perf"

  enum Step {
    case wait(Double)
    case mark(String)
    case open(String)
    case scroll(seconds: Double, speed: Double)
    case window(width: Int, height: Int)
    case resize(seconds: Double, narrow: Int, wide: Int)
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

  /// The Mac window the benchmark sizes: wide enough for the subs sidebar, feed and post columns.
  static let macWindow = (width: 1440, height: 900)

  /// The iPhone scenario in a fixed Mac window, then dragging the window narrower and back, which
  /// lays every column out again each frame, and opening posts one after another with the post
  /// column showing (as links, so each stacks on the last; last, as the stack stays).
  static let macScenario: [Step] = {
    let start: [Step] = [.wait(1), .window(width: macWindow.width, height: macWindow.height)]
    let resize: [Step] = [.wait(1), .mark("resize_start"), .resize(seconds: 4, narrow: 820, wide: macWindow.width), .wait(4.5),
                          .resize(seconds: 4, narrow: 820, wide: macWindow.width), .wait(4.5), .mark("resize_end")]
    let posts: [Step] = (2 ..< 8).flatMap { i -> [Step] in [.open("helioapp://r/pics/comments/pf\(String(format: "%04d", i))"), .wait(1.5)] }
    let more: [Step] = resize + [.wait(2), .mark("switch_start")] + posts + [.mark("switch_end")]
    let base = scenario.dropLast(3) // through cscroll_end
    return start + base + more + [.wait(2), .mark("end"), .wait(1)]
  }()

  // MARK: Build

  static func build(label: String, repo: URL, spm: String?, mac: Bool) {
    if mac {
      return buildMac(label: label, repo: repo, spm: spm)
    }
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
    // Not `check`: failing exits without running `defer`, which restores the smoke tests.
    if shell(command, log: dir.appendingPathComponent("build.log"), check: false).status != 0 {
      if let original {
        try? original.write(to: smoke, atomically: true, encoding: .utf8)
      }
      fail("build failed, see \(dir.path)/build.log")
    }
    print("built")
  }

  /// A Release Mac Catalyst build, unsigned (the linker signs it ad hoc), under its own bundle id
  /// and without its URL schemes. Unprovisioned, it can't use the keychain; the shim stands in.
  static func buildMac(label: String, repo: URL, spm: String?) {
    let dir = Paths.label(label)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var command = ["xcodebuild", "-project", repo.appendingPathComponent("App/Helio.xcodeproj").path, "-scheme", "Helio",
                   "-configuration", "Release", "-destination", "platform=macOS,variant=Mac Catalyst,arch=\(arch)",
                   "-derivedDataPath", dir.appendingPathComponent("build").path, "-skipPackagePluginValidation",
                   "CODE_SIGNING_ALLOWED=NO", "build"]
    if let spm {
      command += ["-clonedSourcePackagesDirPath", URL(fileURLWithPath: spm).path]
    }
    print("building \(repo.path) for Mac as \(label) (log: \(dir.path)/build.log)")
    if shell(command, log: dir.appendingPathComponent("build.log"), check: false).status != 0 {
      fail("build failed, see \(dir.path)/build.log")
    }
    let app = macApp(label)
    let plist = app.appendingPathComponent("Contents/Info.plist").path
    shell(["/usr/libexec/PlistBuddy", "-c", "Set :CFBundleIdentifier \(macBundleID)", plist])
    shell(["/usr/libexec/PlistBuddy", "-c", "Delete :CFBundleURLTypes", plist], check: false)
    shell(["codesign", "--force", "--deep", "--sign", "-", app.path])
    print("built \(app.path)")
  }

  static func macApp(_ label: String) -> URL {
    Paths.label(label).appendingPathComponent("build/Build/Products/Release-maccatalyst/Helio.app")
  }

  static func isMac(_ label: String) -> Bool {
    FileManager.default.fileExists(atPath: macApp(label).path)
  }

  static let arch: String = {
    var system = utsname()
    uname(&system)
    return withUnsafeBytes(of: system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
  }()

  // MARK: Shim

  /// The shim, built for the simulator or Mac Catalyst when missing or older than its source.
  static func shim(mac: Bool = false) -> URL {
    let source = Paths.tool.appendingPathComponent("Shim/HelioPerfShim.swift")
    let out = Paths.work.appendingPathComponent(mac ? "HelioPerfShim-mac.dylib" : "HelioPerfShim.dylib")
    if let built = modificationDate(out), let edited = modificationDate(source), built > edited {
      return out
    }
    try? FileManager.default.createDirectory(at: Paths.work, withIntermediateDirectories: true)
    let sdkName = mac ? "macosx" : "iphonesimulator"
    let sdk = shell(["xcrun", "--sdk", sdkName, "--show-sdk-path"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
    // Mac Catalyst's UIKit lives in the macOS SDK's iOSSupport tree.
    let catalyst = mac ? ["-Fsystem", "\(sdk)/System/iOSSupport/System/Library/Frameworks", "-I", "\(sdk)/System/iOSSupport/usr/lib/swift",
                          "-L", "\(sdk)/System/iOSSupport/usr/lib/swift"] : []
    shell(["xcrun", "--sdk", sdkName, "swiftc", "-target", mac ? "\(arch)-apple-ios26.0-macabi" : "\(arch)-apple-ios26.0-simulator",
           "-sdk", sdk] + catalyst + ["-emit-library", "-O", "-swift-version", "5", "-module-name", "HelioPerfShim",
                                      "-Xlinker", "-init", "-Xlinker", "_helio_perf_init", source.path, "-o", out.path])
    return out
  }

  // MARK: Runs

  static func run(label: String, runs: Int, profile: Bool) {
    if isMac(label) {
      return runMac(label: label, runs: runs, profile: profile)
    }
    let dir = Paths.label(label)
    let products = dir.appendingPathComponent("build/Build/Products")
    guard let xctestrun = (try? FileManager.default.contentsOfDirectory(atPath: products.path))?.first(where: { $0.hasSuffix(".xctestrun") }) else {
      fail("no build for \(label); run: perf build \(label)")
    }
    let udid = Simulator.boot(), shim = shim().path, fixtures = Fixtures.ensure().path
    // Results of an earlier batch with more runs would otherwise count in this one's medians.
    for stale in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where stale.hasPrefix("run") {
      try? FileManager.default.removeItem(at: dir.appendingPathComponent(stale))
    }
    var complete = 0
    for i in 1 ... runs {
      let log = dir.appendingPathComponent("run\(i).log"), commands = dir.appendingPathComponent("run\(i).cmd")
      let trace = dir.appendingPathComponent("run\(i).trace")
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
      let recorder = profile ? record(pid: pid, device: udid, to: trace) : nil
      play(scenario, commands: commands)
      if let recorder {
        recorder.interrupt()
        recorder.waitUntilExit()
      }
      shell(["xcrun", "simctl", "terminate", udid, bundleID], check: false)
      if finished(run: i, log: log, trace: profile ? trace : nil, dir: dir) {
        complete += 1
      }
    }
    guard complete > 0 else { fail("no complete runs") }
    Metrics.printSummary(label)
  }

  /// Time Profiler attached to a process, in the simulator or, without a device, on this Mac.
  static func record(pid: String, device: String?, to trace: URL) -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["xctrace", "record", "--template", "Time Profiler"] + (device.map { ["--device", $0] } ?? [])
      + ["--attach", pid, "--output", trace.path, "--time-limit", "240s"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    return process
  }

  /// Whether a run went through the whole scenario, saying why not when it didn't.
  static func finished(run i: Int, log: URL, trace: URL?, dir: URL) -> Bool {
    let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
    guard RunLog(text: text).marks["end"] != nil else {
      print("run \(i): didn't finish, see \(log.path)")
      return false
    }
    guard !text.contains(" open_failed") else {
      print("run \(i): a deep link didn't open, see \(log.path)")
      return false
    }
    if text.contains(" no_scroll_view") {
      print("run \(i): nothing to scroll when asked (comments not loaded 5 s after opening the post?)")
    }
    if text.contains(" no_window") || text.contains(" window_failed") {
      print("run \(i): couldn't size the window, see \(log.path)")
    }
    if let trace, !Profile.export(trace, to: dir.appendingPathComponent("run\(i).tp.xml")) {
      print("run \(i): couldn't export the trace")
    }
    print("run \(i) ok")
    return true
  }

  // MARK: Mac runs

  /// Each run starts from an empty home folder (`CFFIXED_USER_HOME`: caches, Core Data, saved
  /// state) and empty preferences, launches once to sign in and load the account like a first
  /// launch, then again as a returning user for the measured scenario. The window comes to the
  /// front for the run; leave the Mac alone while it runs, as other work skews the timings.
  static func runMac(label: String, runs: Int, profile: Bool) {
    let dir = Paths.label(label), app = macApp(label)
    let executable = app.appendingPathComponent("Contents/MacOS/Helio")
    let shim = shim(mac: true).path, fixtures = Fixtures.ensure().path
    for stale in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where stale.hasPrefix("run") {
      try? FileManager.default.removeItem(at: dir.appendingPathComponent(stale))
    }
    var complete = 0
    for i in 1 ... runs {
      let log = dir.appendingPathComponent("run\(i).log"), commands = dir.appendingPathComponent("run\(i).cmd")
      let trace = dir.appendingPathComponent("run\(i).trace"), home = dir.appendingPathComponent("run\(i).home")
      quitMac(executable)
      try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
      shell(["defaults", "delete", macBundleID], check: false)
      let env = ["DYLD_INSERT_LIBRARIES": shim, "PERF_FIXTURES": fixtures, "PERF_SEED_CREDENTIAL": "1", "PERF_MEMORY_KEYCHAIN": "1",
                 "PERF_SKIP_WHATS_NEW": "1", "CFFIXED_USER_HOME": home.path]

      // First launch: sign in, account, subscriptions. The keychain is in memory, so the
      // measured launch signs in again, like a launch after the hour-long token expired.
      // A launch now and then never draws its window; try again before giving up on the run.
      let setupLog = URL(fileURLWithPath: log.path + ".setup")
      var signedIn = false
      for _ in 1 ... 2 where !signedIn {
        let setupCommands = dir.appendingPathComponent("run\(i).setup.cmd")
        FileManager.default.createFile(atPath: setupCommands.path, contents: nil)
        try? FileManager.default.removeItem(at: setupLog)
        let setup = launchMac(executable, env: env.merging(["PERF_LOG": setupLog.path, "PERF_CMD": setupCommands.path]) { $1 })
        play([.wait(1), .window(width: macWindow.width, height: macWindow.height), .wait(9)], commands: setupCommands)
        quitMac(executable, setup)
        signedIn = (try? String(contentsOf: setupLog, encoding: .utf8))?.contains("/api/v1/me") == true
      }
      guard signedIn else {
        print("run \(i): the setup launch didn't load the account, see \(setupLog.path)")
        continue
      }

      // The measured launch opens a new window rather than restoring the setup launch's: a
      // restored session can come back without one.
      try? FileManager.default.removeItem(at: home.appendingPathComponent("Library/Saved Application State"))
      FileManager.default.createFile(atPath: commands.path, contents: nil)
      let process = launchMac(executable, env: env.merging(["PERF_LOG": log.path, "PERF_CMD": commands.path]) { $1 })
      let recorder = profile ? record(pid: "\(process.processIdentifier)", device: nil, to: trace) : nil
      play(macScenario, commands: commands)
      if let recorder {
        recorder.interrupt()
        recorder.waitUntilExit()
      }
      quitMac(executable, process)
      if finished(run: i, log: log, trace: profile ? trace : nil, dir: dir) {
        complete += 1
      }
    }
    shell(["defaults", "delete", macBundleID], check: false)
    guard complete > 0 else { fail("no complete runs") }
    Metrics.printSummary(label)
  }

  static func launchMac(_ executable: URL, env: [String: String]) -> Process {
    let process = Process()
    process.executableURL = executable
    process.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      fail("can't launch \(executable.path): \(error)")
    }
    return process
  }

  /// Ends a perf launch, and any left over from an interrupted run.
  static func quitMac(_ executable: URL, _ process: Process? = nil) {
    if let process, process.isRunning {
      process.terminate()
      process.waitUntilExit()
    }
    shell(["pkill", "-f", executable.path], check: false)
    Thread.sleep(forTimeInterval: 1)
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
      case let .window(width, height): send("window \(width) \(height)")
      case let .resize(seconds, narrow, wide): send("resize \(seconds) \(narrow) \(wide)")
      }
    }
  }
}
