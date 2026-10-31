// Network fixtures, metrics and a driver for Helio perf runs in the simulator, loaded into the
// app with DYLD_INSERT_LIBRARIES by `perf`. Never part of the app. `perf` builds it with
// `-Xlinker -init -Xlinker _helio_perf_init`, so `start()` runs when the library loads.
//
// - Serves every http(s) request from $PERF_FIXTURES (see Fixtures.swift) after a delay
//   ($PERF_LATENCY_MS for Reddit, $PERF_OTHER_LATENCY_MS for everything else) and generates
//   images, so nothing reaches the network.
// - Writes to $PERF_LOG: `R <ms> <method> <url>` per request, `M <ms> cpu= main= fp= peak= hitch=
//   hitches= frames=` every 250 ms, `P <ms> <name>` markers, and `S`/`W` clock lines. Times are ms
//   since the library loaded. A hitch is a main-thread frame over 1.5x the display interval.
// - Runs commands appended to $PERF_CMD, one per line: `<seq> mark <name>`, `<seq> open <url>`
//   (hands the URL to the scene like a tapped link, without the system's "Open in" prompt) and
//   `<seq> scroll <seconds> <points per second>` (scrolls the largest visible scroll view).
// - With $PERF_SEED_CREDENTIAL set, stores a placeholder Reddit account in the keychain.

import Foundation
import ObjectiveC
import QuartzCore
import Security
import UIKit

@_cdecl("helio_perf_init")
public func helioPerfInit() {
  Shim.start()
}

enum Shim {
  static let env = ProcessInfo.processInfo.environment
  static let fixtures = URL(fileURLWithPath: env["PERF_FIXTURES"] ?? "/nonexistent")
  static let t0 = CACurrentMediaTime()
  static let logQueue = DispatchQueue(label: "helio.perf.log")
  static var mainThread = mach_thread_self()
  static var timers: [DispatchSourceTimer] = []

  static var now: Double {
    (CACurrentMediaTime() - t0) * 1000
  }

  static func log(_ line: String) {
    guard let path = env["PERF_LOG"] else { return }
    logQueue.async {
      if !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: nil)
      }
      guard let handle = FileHandle(forWritingAtPath: path) else { return }
      handle.seekToEndOfFile()
      handle.write(Data((line + "\n").utf8))
      try? handle.close()
    }
  }

  static func start() {
    mainThread = mach_thread_self()
    if env["PERF_SEED_CREDENTIAL"] != nil {
      seedCredential()
    }
    interceptSessions()
    log(String(format: "S %.0f start", t0 * 1000))
    log(String(format: "W %.3f wallclock", Date().timeIntervalSince1970))
    DispatchQueue.main.async { FrameWatch.shared.start() }
    timers = [
      timer(every: 250) { sample() },
      timer(every: 50) { Driver.runCommands() },
    ]
  }

  static func timer(every ms: Int, _ handler: @escaping () -> Void) -> DispatchSourceTimer {
    let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
    timer.schedule(deadline: .now(), repeating: .milliseconds(ms), leeway: .milliseconds(5))
    timer.setEventHandler(handler: handler)
    timer.resume()
    return timer
  }

  // MARK: Metrics

  static func sample() {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1000 + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1000

    var info = thread_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
    let threadResult = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { thread_info(mainThread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count) }
    }
    let mainCPU = threadResult == KERN_SUCCESS
      ? Double(info.user_time.seconds + info.system_time.seconds) * 1000 + Double(info.user_time.microseconds + info.system_time.microseconds) / 1000
      : 0

    var vm = task_vm_info_data_t()
    var vmCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let vmResult = withUnsafeMutablePointer(to: &vm) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount) }
    }
    let footprint = vmResult == KERN_SUCCESS ? Double(vm.phys_footprint) / 1_048_576 : 0
    let peak = vmResult == KERN_SUCCESS ? Double(vm.ledger_phys_footprint_peak) / 1_048_576 : 0

    let frames = FrameWatch.shared.snapshot
    log(String(format: "M %.0f cpu=%.0f main=%.0f fp=%.1f peak=%.1f hitch=%.0f hitches=%d frames=%d",
               now, cpu, mainCPU, footprint, peak, frames.hitchMs, frames.hitches, frames.frames))
  }

  // MARK: Network

  /// Alamofire and Nuke make their own sessions, which ignore registered protocol classes.
  static func interceptSessions() {
    URLProtocol.registerClass(FixtureProtocol.self)

    let factory = NSSelectorFromString("sessionWithConfiguration:delegate:delegateQueue:")
    if let method = class_getClassMethod(URLSession.self, factory) {
      typealias Factory = @convention(c) (AnyObject, Selector, URLSessionConfiguration, AnyObject?, OperationQueue?) -> AnyObject
      let original = unsafeBitCast(method_getImplementation(method), to: Factory.self)
      let replacement: @convention(block) (AnyObject, URLSessionConfiguration, AnyObject?, OperationQueue?) -> AnyObject = { cls, config, delegate, queue in
        config.protocolClasses = [FixtureProtocol.self] + (config.protocolClasses ?? []).filter { $0 != FixtureProtocol.self }
        return original(cls, factory, config, delegate, queue)
      }
      method_setImplementation(method, imp_implementationWithBlock(replacement))
    }

    let getter = #selector(getter: URLSessionConfiguration.protocolClasses)
    let configClass: AnyClass = NSClassFromString("__NSCFURLSessionConfiguration") ?? URLSessionConfiguration.self
    if let method = class_getInstanceMethod(configClass, getter) {
      typealias Getter = @convention(c) (AnyObject, Selector) -> NSArray?
      let original = unsafeBitCast(method_getImplementation(method), to: Getter.self)
      let replacement: @convention(block) (AnyObject) -> NSArray = { config in
        let others = (original(config, getter) as? [AnyClass] ?? []).filter { $0 != FixtureProtocol.self }
        return ([FixtureProtocol.self] + others) as NSArray
      }
      method_setImplementation(method, imp_implementationWithBlock(replacement))
    }
  }

  /// A placeholder account in the keychain format Helio reads, with no access token, so the first
  /// request refreshes it like a launch after the hour-long token expired.
  static func seedCredential() {
    let credential: [String: String] = [
      "id": "11111111-1111-1111-1111-111111111111", "apiAppID": "fixturefixturefixture1", "apiAppSecret": "fixture",
      "refreshToken": "fixture-refresh", "userName": "fixture_user",
    ]
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.sertacozercan.helio.reddit-multi-credentials",
      kSecAttrAccount as String: credential["id"]!,
    ]
    SecItemDelete(query as CFDictionary)
    var add = query
    add[kSecValueData as String] = try? JSONSerialization.data(withJSONObject: credential)
    SecItemAdd(add as CFDictionary, nil)
  }
}

// MARK: - Fixture responses

final class FixtureProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool {
    ["http", "https"].contains(request.url?.scheme?.lowercased() ?? "")
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let url = request.url else { return }
    let method = request.httpMethod ?? "GET"
    Shim.log(String(format: "R %.0f %@ %@", Shim.now, method, url.absoluteString))
    let reddit = url.host?.lowercased().hasSuffix("reddit.com") ?? false
    let (status, type, body) = Self.response(url: url, method: method)
    let latency = Double(Shim.env[reddit ? "PERF_LATENCY_MS" : "PERF_OTHER_LATENCY_MS"] ?? "") ?? (reddit ? 150 : 60)
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + latency / 1000) { [self] in
      let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                     headerFields: ["Content-Type": type, "Content-Length": "\(body.count)"])!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: body)
      client?.urlProtocolDidFinishLoading(self)
    }
  }

  override func stopLoading() {}

  static func file(_ path: String) -> Data? {
    try? Data(contentsOf: Shim.fixtures.appendingPathComponent(path))
  }

  static func json(_ object: Any) -> Data {
    (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
  }

  static func jsonFile(_ path: String) -> Any? {
    file(path).flatMap { try? JSONSerialization.jsonObject(with: $0) }
  }

  static func query(_ url: URL, _ name: String) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
  }

  static func list(_ url: URL, _ name: String) -> [String] {
    (query(url, name) ?? "").split(separator: ",").map(String.init)
  }

  static func response(url: URL, method: String) -> (Int, String, Data) {
    let host = url.host?.lowercased() ?? "", path = url.path, ext = url.pathExtension.lowercased()
    let parts = url.pathComponents.filter { $0 != "/" }
    let reddit = host.hasSuffix("reddit.com") && !host.hasPrefix("i.") && !host.contains("preview")
    var type = "application/json"
    let body: Data?

    if ["mp4", "m3u8", "mov"].contains(ext) {
      body = nil // No media in the fixtures: videos fail to load.
    } else if !reddit, host == "fixture.local" || ["jpg", "jpeg", "png", "gif", "webp"].contains(ext) || host.hasSuffix("redd.it") || host.hasSuffix("ytimg.com") {
      body = Images.jpeg(named: url.lastPathComponent)
      type = "image/jpeg"
    } else if !reddit {
      body = file("og.html")
      type = "text/html; charset=utf-8"
    } else if path.contains("access_token") {
      body = file("token.json")
    } else if path.hasPrefix("/api/v1/me") {
      body = file("me.json")
    } else if path.hasPrefix("/subreddits/mine") {
      body = file("subs_mine.json")
    } else if path.hasPrefix("/api/multi/mine") {
      body = file("multis.json")
    } else if path.hasPrefix("/api/info") {
      let subreddits = list(url, "sr_name").compactMap { jsonFile("about/\($0.lowercased()).json") }
      let things = list(url, "id").compactMap { $0.hasPrefix("t5_") ? jsonFile("about/\($0.dropFirst(3)).json") : jsonFile("things/\($0).json") }
      body = json(["kind": "Listing", "data": ["children": subreddits + things, "after": NSNull(), "dist": subreddits.count + things.count]])
    } else if path.hasPrefix("/api/user_data_by_account_ids") {
      var users: [String: Any] = [:]
      for id in list(url, "ids") where id.hasPrefix("t2_") {
        let name = String(id.dropFirst(3))
        users[id] = ["name": name, "created_utc": 1_500_000_000, "link_karma": 10, "comment_karma": 20,
                     "profile_img": "https://fixture.local/img/avatar_\(name).jpg?size=256", "profile_over_18": false]
      }
      body = json(users)
    } else if path.hasPrefix("/api/morechildren") {
      body = file("morechildren.json")
    } else if path.hasPrefix("/message/") {
      body = file("inbox.json")
    } else if method == "POST" {
      body = file("ok.json")
    } else if parts.count >= 3, parts[0] == "r", parts[2].hasPrefix("about") {
      body = parts.count == 3 ? file("about/\(parts[1].lowercased()).json") : json(["kind": "Listing", "data": ["children": []], "rules": []])
    } else if parts.count >= 4, parts[0] == "r", parts[2] == "comments" {
      body = file("comments/\((parts[3] as NSString).deletingPathExtension).json")
    } else if parts.count >= 3, parts[0] == "user", parts[2].hasPrefix("about") {
      body = json(["kind": "t2", "data": ["name": parts[1], "id": parts[1], "created_utc": 1_500_000_000, "link_karma": 1, "comment_karma": 1, "icon_img": ""]])
    } else if path.contains("flair") {
      body = json([Any]())
    } else {
      // Feeds ("/", "/best", "/r/x/hot", ...), paged by `after`.
      let after = query(url, "after") ?? ""
      body = file("feed_\(after.isEmpty ? "first" : after).json") ?? file("empty_listing.json")
    }
    guard let body else { return (404, "application/json", Data("{}".utf8)) }
    return (200, type, body)
  }
}

/// JPEGs for image URLs: `p<n>` post images, `t<n>` thumbnails, anything else an avatar-sized
/// square. Sizes match the dimensions the fixtures declare in their preview data.
enum Images {
  static let sizes: [String: CGSize] = [
    "p1": CGSize(width: 1200, height: 675), "p2": CGSize(width: 1200, height: 1200), "p3": CGSize(width: 1200, height: 900),
    "p4": CGSize(width: 1200, height: 1200), "p5": CGSize(width: 900, height: 1200), "p6": CGSize(width: 1200, height: 1200),
    "p7": CGSize(width: 600, height: 2000),
  ]
  static let cache = NSCache<NSString, NSData>()

  static func jpeg(named name: String) -> Data {
    if let cached = cache.object(forKey: name as NSString) {
      return cached as Data
    }
    let stem = (name as NSString).deletingPathExtension
    let size = sizes[stem] ?? (stem.hasPrefix("t") ? CGSize(width: 140, height: 140) : CGSize(width: 256, height: 256))
    let seed = name.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1.value) }
    let format = UIGraphicsImageRendererFormat.preferred()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
      let top = UIColor(hue: CGFloat(seed % 360) / 360, saturation: 0.55, brightness: 0.85, alpha: 1)
      let bottom = UIColor(hue: CGFloat((seed / 360) % 360) / 360, saturation: 0.7, brightness: 0.45, alpha: 1)
      let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top.cgColor, bottom.cgColor] as CFArray, locations: nil)!
      context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
      // Some detail, so the JPEG isn't trivially small.
      for i in 0 ..< 40 {
        UIColor(white: CGFloat(i % 5) / 5, alpha: 0.25).setFill()
        let x = CGFloat((seed &* UInt64(i + 3) &* 7) % UInt64(max(size.width, 1)))
        let y = CGFloat((seed &* UInt64(i + 5) &* 13) % UInt64(max(size.height, 1)))
        UIBezierPath(ovalIn: CGRect(x: x, y: y, width: size.width / 6, height: size.height / 6)).fill()
      }
    }
    let data = image.jpegData(compressionQuality: 0.8) ?? Data()
    cache.setObject(data as NSData, forKey: name as NSString)
    return data
  }
}

// MARK: - Frames and driver

final class FrameWatch: NSObject {
  static let shared = FrameWatch()
  private let lock = NSLock()
  private var last: CFTimeInterval = 0
  private var hitchMs: Double = 0
  private var hitches = 0
  private var frames = 0

  var snapshot: (hitchMs: Double, hitches: Int, frames: Int) {
    lock.withLock { (hitchMs, hitches, frames) }
  }

  func start() {
    let link = CADisplayLink(target: self, selector: #selector(tick))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
    link.add(to: .main, forMode: .common)
  }

  @objc private func tick(_ link: CADisplayLink) {
    let expected = link.duration > 0 ? link.duration : 1.0 / 60
    lock.withLock {
      if last > 0 {
        let delta = link.timestamp - last
        if delta > expected * 1.5 {
          hitchMs += (delta - expected) * 1000
          hitches += 1
        }
      }
      last = link.timestamp
      frames += 1
    }
  }
}

final class Scroller: NSObject {
  weak var scrollView: UIScrollView?
  let speed: Double
  var remaining: Double
  private var last: CFTimeInterval = 0
  private var link: CADisplayLink?

  init(scrollView: UIScrollView, speed: Double, seconds: Double) {
    self.scrollView = scrollView
    self.speed = speed
    remaining = seconds
  }

  func start() {
    let link = CADisplayLink(target: self, selector: #selector(tick))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  @objc private func tick(_ link: CADisplayLink) {
    let dt = last > 0 ? link.timestamp - last : link.duration
    last = link.timestamp
    if let scrollView {
      let minY = -scrollView.adjustedContentInset.top
      let maxY = max(minY, scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height)
      var offset = scrollView.contentOffset
      offset.y = min(maxY, max(minY, offset.y + speed * dt))
      scrollView.setContentOffset(offset, animated: false)
    }
    remaining -= dt
    if remaining <= 0 || scrollView == nil {
      link.invalidate()
      self.link = nil
      Shim.log(String(format: "P %.0f scrolled", Shim.now))
    }
  }
}

enum Driver {
  static var lastCommand = 0
  static var scroller: Scroller?

  static func runCommands() {
    guard let path = Shim.env["PERF_CMD"], let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
    for line in text.split(separator: "\n") {
      let fields = line.split(separator: " ").map(String.init)
      guard fields.count >= 3, let seq = Int(fields[0]), seq > lastCommand else { continue }
      lastCommand = seq
      switch fields[1] {
      case "mark":
        Shim.log(String(format: "P %.0f %@", Shim.now, fields[2]))
      case "open":
        guard let url = URL(string: fields[2]) else { continue }
        DispatchQueue.main.async { open(url) }
      case "scroll" where fields.count >= 4:
        let seconds = Double(fields[2]) ?? 0, speed = Double(fields[3]) ?? 0
        DispatchQueue.main.async { scroll(seconds: seconds, speed: speed) }
      default:
        break
      }
    }
  }

  static func open(_ url: URL) {
    for scene in UIApplication.shared.connectedScenes {
      guard let delegate = scene.delegate, delegate.responds(to: #selector(UISceneDelegate.scene(_:openURLContexts:))),
            let contextClass = NSClassFromString("UIOpenURLContext") as? NSObject.Type else { continue }
      let context = contextClass.init()
      context.setValue(url, forKey: "URL")
      guard let urlContext = context as? UIOpenURLContext else { continue }
      delegate.scene?(scene, openURLContexts: [urlContext])
      Shim.log(String(format: "P %.0f opened", Shim.now))
      return
    }
    Shim.log(String(format: "P %.0f open_failed", Shim.now))
  }

  static func scroll(seconds: Double, speed: Double) {
    guard let scrollView = mainScrollView() else {
      Shim.log(String(format: "P %.0f no_scroll_view", Shim.now))
      return
    }
    let scroller = Scroller(scrollView: scrollView, speed: speed, seconds: seconds)
    scroller.start()
    self.scroller = scroller
  }

  /// The largest visible scroll view that can scroll vertically: the feed or the post's comments.
  static func mainScrollView() -> UIScrollView? {
    let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
    guard let window else { return nil }
    var best: (UIScrollView, CGFloat)?
    func visit(_ view: UIView) {
      guard !view.isHidden, view.alpha > 0.01 else { return }
      if let scrollView = view as? UIScrollView, scrollView.contentSize.height > scrollView.bounds.height * 1.2 {
        let visible = scrollView.convert(scrollView.bounds, to: window).intersection(window.bounds)
        let area = visible.isNull ? 0 : visible.width * visible.height
        if area > (best?.1 ?? 0) {
          best = (scrollView, area)
        }
      }
      view.subviews.forEach(visit)
    }
    visit(window)
    return best?.0
  }
}
