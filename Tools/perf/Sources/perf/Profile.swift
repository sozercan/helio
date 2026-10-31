import Foundation

/// Time Profiler traces recorded by `perf bench --profile`: main-thread samples on the run log's
/// clock, the stalls in a window and what ran in them.
enum Profile {
  struct Frame: Hashable {
    let name: String
    let binary: String
  }

  struct Sample {
    let time: Double
    let frames: [Frame]
  }

  /// Frames every sample shares, left out of the breakdowns.
  static let rootFrames = ["start", "main", "UIApplicationMain", "GSEventRunModal", "CFRunLoopRun", "__CFRunLoop", "runApp",
                           "App.main", "KitRendererCommon", "HelioApp.$main", "start_sim"]

  /// Writes the trace's time-profile table as XML.
  static func export(_ trace: URL, to file: URL) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = ["xctrace", "export", "--input", trace.path, "--xpath", #"/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]"#]
    FileManager.default.createFile(atPath: file.path, contents: nil)
    guard let handle = try? FileHandle(forWritingTo: file) else { return false }
    process.standardOutput = handle
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return false }
    process.waitUntilExit()
    try? handle.close()
    return process.terminationStatus == 0
  }

  /// Main-thread samples of a profiled run, on the run log's clock.
  static func load(label: String, run: Int) -> (samples: [Sample], log: RunLog) {
    let dir = Paths.label(label)
    let xml = dir.appendingPathComponent("run\(run).tp.xml"), trace = dir.appendingPathComponent("run\(run).trace")
    guard FileManager.default.fileExists(atPath: xml.path),
          let text = try? String(contentsOf: dir.appendingPathComponent("run\(run).log"), encoding: .utf8)
    else {
      fail("no profile for run \(run); run: perf bench \(label) --runs 1 --profile")
    }
    let log = RunLog(text: text)
    let toc = shell(["xcrun", "xctrace", "export", "--input", trace.path, "--toc"]).output
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let range = toc.range(of: #"(?<=<start-date>)[^<]+"#, options: .regularExpression),
          let start = formatter.date(from: String(toc[range])), let wall = log.wallClock
    else {
      fail("can't line the trace up with the run log")
    }
    let parser = TimeProfileParser(offset: (start.timeIntervalSince1970 - wall) * 1000)
    guard let xmlParser = XMLParser(contentsOf: xml) else { fail("can't read \(xml.path)") }
    xmlParser.delegate = parser
    xmlParser.parse()
    return (parser.samples.sorted { $0.time < $1.time }, log)
  }

  static func window(_ samples: [Sample], _ log: RunLog, from start: String, to end: String) -> [Sample] {
    let lo = log.marks[start] ?? 0, hi = log.marks[end] ?? .infinity
    return samples.filter { $0.time >= lo && $0.time <= hi }
  }

  /// Runs of main-thread samples with no gap, which is how a busy main thread looks at ~1 ms per sample.
  static func busyRuns(_ samples: [Sample]) -> [[Sample]] {
    var runs: [[Sample]] = [], current: [Sample] = []
    for sample in samples {
      if let last = current.last, sample.time - last.time > 2.5 {
        runs.append(current)
        current = []
      }
      current.append(sample)
    }
    if !current.isEmpty {
      runs.append(current)
    }
    return runs
  }

  static func stalls(label: String, run: Int, from start: String, to end: String, minimum: Double, top: Int) {
    let (all, log) = load(label: label, run: run)
    let samples = window(all, log, from: start, to: end)
    let stalls = busyRuns(samples).filter { $0.last!.time - $0.first!.time >= minimum }
    let total = stalls.reduce(0) { $0 + $1.last!.time - $1.first!.time }
    print("\(start)..\(end): \(samples.count) main-thread samples (~ms), \(stalls.count) stalls of \(Int(minimum))+ ms totaling \(Int(total)) ms")
    print("  at ms: " + stalls.map { "\(Int($0.first!.time))+\(Int($0.last!.time - $0.first!.time))" }.joined(separator: " "))
    var inclusive: [Frame: Int] = [:]
    let count = stalls.reduce(0) { $0 + $1.count }
    for sample in stalls.joined() {
      for frame in Set(sample.frames) where !rootFrames.contains(where: { frame.name.hasPrefix($0) || frame.name.contains($0) }) {
        inclusive[frame, default: 0] += 1
      }
    }
    func show(_ entries: [(Frame, Int)]) {
      for (frame, n) in entries.sorted(by: { $0.1 > $1.1 }).prefix(top) {
        print(String(format: "  %6d %5.1f%%  ", n, Double(n) * 100 / Double(max(count, 1))) + "\(frame.name.prefix(110))  [\(frame.binary)]")
      }
    }
    print("\nInside the stalls, by frame (inclusive):")
    show(Array(inclusive))
    print("\nApp frames inside the stalls:")
    show(inclusive.filter { $0.key.binary == "Helio" }.map { ($0.key, $0.value) })
  }

  static func callers(label: String, run: Int, symbol: String, from start: String, to end: String, depth: Int, top: Int) {
    let (all, log) = load(label: label, run: run)
    var chains: [String: Int] = [:], hits = 0
    for sample in window(all, log, from: start, to: end) {
      guard let index = sample.frames.firstIndex(where: { $0.name.contains(symbol) }) else { continue }
      hits += 1
      let chain = sample.frames.dropFirst(index + 1).prefix(depth).map { String($0.name.prefix(80)) }.joined(separator: " < ")
      chains[chain, default: 0] += 1
    }
    print("\(hits) main-thread samples in frames matching \"\(symbol)\"; callers:")
    for (chain, n) in chains.sorted(by: { $0.value > $1.value }).prefix(top) {
      print(String(format: "  %5d  ", n) + chain)
    }
  }
}

/// Reads the time-profile table: each `row` is a sample whose fields are elements, or `ref`s to
/// elements with that `id` seen earlier.
private final class TimeProfileParser: NSObject, XMLParserDelegate {
  final class Node {
    let tag: String
    let attributes: [String: String]
    var children: [Node] = []
    var text = ""

    init(tag: String, attributes: [String: String]) {
      self.tag = tag
      self.attributes = attributes
    }
  }

  let offset: Double
  var samples: [Profile.Sample] = []
  private var byID: [String: Node] = [:]
  private var stack: [Node] = []

  init(offset: Double) {
    self.offset = offset
  }

  func parser(_: XMLParser, didStartElement name: String, namespaceURI _: String?, qualifiedName _: String?, attributes: [String: String] = [:]) {
    guard name == "row" || !stack.isEmpty else { return }
    let node = Node(tag: name, attributes: attributes)
    stack.last?.children.append(node)
    stack.append(node)
    if let id = attributes["id"] {
      byID[id] = node
    }
  }

  func parser(_: XMLParser, foundCharacters string: String) {
    stack.last?.text += string
  }

  func parser(_: XMLParser, didEndElement name: String, namespaceURI _: String?, qualifiedName _: String?) {
    guard let node = stack.popLast(), node.tag == "row", stack.isEmpty else { return }
    var time: Double?, thread: Node?, backtrace: Node?
    for child in node.children.map(resolve) {
      switch child.tag {
      case "sample-time": time = Double(child.text).map { $0 / 1_000_000 + offset }
      case "thread": thread = child
      case "backtrace", "tagged-backtrace": backtrace = child
      default: break
      }
    }
    guard let time, let thread, let backtrace, thread.attributes["fmt"]?.contains("Main Thread") == true else { return }
    let frames = backtrace.children.filter { $0.tag == "frame" }.map(resolve).map { frame in
      Profile.Frame(name: frame.attributes["name"] ?? "?",
                    binary: frame.children.first { $0.tag == "binary" }.map(resolve)?.attributes["name"] ?? "")
    }
    samples.append(Profile.Sample(time: time, frames: frames))
  }

  private func resolve(_ node: Node) -> Node {
    node.attributes["ref"].flatMap { byID[$0] } ?? node
  }
}
