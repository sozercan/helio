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
// - On Mac: `<seq> window <width> <height>` sizes the window, `<seq> resize <seconds> <min width>
//   <max width>` drags its width from max to min and back like a live resize. With
//   $PERF_MEMORY_KEYCHAIN set, the keychain is an in-memory store: an unprovisioned Mac Catalyst
//   build can't use the real one, and runs then never touch the user's. With $PERF_SKIP_WHATS_NEW
//   set, this version's What's New counts as seen.

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
    if env["PERF_SKIP_WHATS_NEW"] != nil, let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
      // WhatsNewKit's UserDefaults store: one key per presented version.
      UserDefaults.standard.set(version, forKey: "WhatsNewKit.\(version)")
    }
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
    var add = query
    add[kSecValueData as String] = try? JSONSerialization.data(withJSONObject: credential)
    // Calls from this library aren't interposed, so the in-memory store is called directly.
    if MemoryKeychain.enabled {
      _ = MemoryKeychain.delete(query)
      _ = MemoryKeychain.add(add)
    } else {
      SecItemDelete(query as CFDictionary)
      SecItemAdd(add as CFDictionary, nil)
    }
  }
}

// MARK: - In-memory keychain

/// Generic and internet passwords kept in memory, in place of the keychain, when
/// $PERF_MEMORY_KEYCHAIN is set. Enough of SecItem for KeychainAccess: matching by class,
/// service, account and server, `kSecMatchLimit` one or all, and returning data, attributes or both.
enum MemoryKeychain {
  static let enabled = Shim.env["PERF_MEMORY_KEYCHAIN"] != nil
  private static let lock = NSLock()
  private nonisolated(unsafe) static var items: [[String: Any]] = []
  private static let identity = [kSecClass, kSecAttrService, kSecAttrAccount, kSecAttrServer, kSecAttrProtocol, kSecAttrPort, kSecAttrPath]
    .map { $0 as String }
  private static let queryOnly = [kSecMatchLimit, kSecReturnData, kSecReturnAttributes, kSecReturnRef, kSecReturnPersistentRef,
                                  kSecUseDataProtectionKeychain, kSecUseAuthenticationContext]
    .map { $0 as String }

  private static func matches(_ item: [String: Any], _ query: [String: Any]) -> Bool {
    identity.allSatisfy { key in
      guard let wanted = query[key] as? NSObject else { return true }
      return (item[key] as? NSObject)?.isEqual(wanted) ?? false
    }
  }

  private static func dictionary(_ cf: CFDictionary) -> [String: Any] {
    (cf as NSDictionary) as? [String: Any] ?? [:]
  }

  static func add(_ attributes: [String: Any]) -> OSStatus {
    lock.withLock {
      guard !items.contains(where: { matches($0, attributes.filter { identity.contains($0.key) }) }) else { return errSecDuplicateItem }
      items.append(attributes.filter { !queryOnly.contains($0.key) })
      return errSecSuccess
    }
  }

  static func copy(_ query: [String: Any], _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
    let found = lock.withLock { items.filter { matches($0, query) } }
    guard !found.isEmpty else { return errSecItemNotFound }
    let all = (query[kSecMatchLimit as String] as? NSObject)?.isEqual(kSecMatchLimitAll) ?? false
    let data = query[kSecReturnData as String] as? Bool ?? false, attributes = query[kSecReturnAttributes as String] as? Bool ?? false
    let values: [Any] = found.compactMap { item in
      if attributes {
        return data ? item : item.filter { $0.key != kSecValueData as String }
      }
      return data ? item[kSecValueData as String] : nil
    }
    if let result, !values.isEmpty {
      result.pointee = (all ? values as NSArray : values[0] as AnyObject) as CFTypeRef
    }
    return errSecSuccess
  }

  static func update(_ query: [String: Any], _ changes: [String: Any]) -> OSStatus {
    lock.withLock {
      var updated = false
      for i in items.indices where matches(items[i], query) {
        items[i].merge(changes) { $1 }
        updated = true
      }
      return updated ? errSecSuccess : errSecItemNotFound
    }
  }

  static func delete(_ query: [String: Any]) -> OSStatus {
    lock.withLock {
      let before = items.count
      items.removeAll { matches($0, query) }
      return items.count < before ? errSecSuccess : errSecItemNotFound
    }
  }

  // The app's calls, through dyld's interpose table below. With the store off they go on to the
  // keychain: calls from this library aren't interposed.
  typealias AddOrCopy = @convention(c) (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
  typealias Update = @convention(c) (CFDictionary, CFDictionary) -> OSStatus
  typealias Delete = @convention(c) (CFDictionary) -> OSStatus

  static let addItem: AddOrCopy = { enabled ? add(dictionary($0)) : SecItemAdd($0, $1) }
  static let copyMatching: AddOrCopy = { enabled ? copy(dictionary($0), $1) : SecItemCopyMatching($0, $1) }
  static let updateItem: Update = { enabled ? update(dictionary($0), dictionary($1)) : SecItemUpdate($0, $1) }
  static let deleteItem: Delete = { enabled ? delete(dictionary($0)) : SecItemDelete($0) }
}

@_cdecl("helio_perf_SecItemAdd")
func perfSecItemAdd(_ attributes: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
  MemoryKeychain.addItem(attributes, result)
}

@_cdecl("helio_perf_SecItemCopyMatching")
func perfSecItemCopyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
  MemoryKeychain.copyMatching(query, result)
}

@_cdecl("helio_perf_SecItemUpdate")
func perfSecItemUpdate(_ query: CFDictionary, _ changes: CFDictionary) -> OSStatus {
  MemoryKeychain.updateItem(query, changes)
}

@_cdecl("helio_perf_SecItemDelete")
func perfSecItemDelete(_ query: CFDictionary) -> OSStatus {
  MemoryKeychain.deleteItem(query)
}

/// dyld's interpose table: (replacement, original) pairs.
@section("__DATA,__interpose") @used
let interposeSecItemAdd: (MemoryKeychain.AddOrCopy, MemoryKeychain.AddOrCopy) = (perfSecItemAdd, SecItemAdd)
@section("__DATA,__interpose") @used
let interposeSecItemCopyMatching: (MemoryKeychain.AddOrCopy, MemoryKeychain.AddOrCopy) = (perfSecItemCopyMatching, SecItemCopyMatching)
@section("__DATA,__interpose") @used
let interposeSecItemUpdate: (MemoryKeychain.Update, MemoryKeychain.Update) = (perfSecItemUpdate, SecItemUpdate)
@section("__DATA,__interpose") @used
let interposeSecItemDelete: (MemoryKeychain.Delete, MemoryKeychain.Delete) = (perfSecItemDelete, SecItemDelete)

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
    // Reddit's web pages (link previews of a post or subreddit), not its API: OAuth, `/api/` or `.json`.
    let webPage = host != "oauth.reddit.com" && !path.hasPrefix("/api/") && !path.hasSuffix(".json")
    let reddit = host.hasSuffix("reddit.com") && !host.hasPrefix("i.") && !host.contains("preview") && !webPage
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
    // The interval the link asked for. `duration` is the display's, which on a 120 Hz Mac display
    // is half the 60 fps asked for, so every frame would count as a hitch.
    let interval = link.targetTimestamp - link.timestamp
    let expected = interval > 0 ? interval : link.duration > 0 ? link.duration : 1.0 / 60
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

/// Drags a Mac window's width from wide to narrow and back over `seconds`, a step per frame,
/// like a live resize: each step lays the window out again. Steps set the AppKit window's frame,
/// as dragging its edge does; `requestGeometryUpdate` would run each one as an animated size
/// transition instead. Logs how many steps it took and their average time.
final class Resizer: NSObject {
  weak var scene: UIWindowScene?
  let seconds: Double, wide: Double, narrow: Double
  private var began: CFTimeInterval = 0
  private var link: CADisplayLink?
  private var steps = 0
  private var stepTime: Double = 0

  init(scene: UIWindowScene, seconds: Double, wide: Double, narrow: Double) {
    self.scene = scene
    self.seconds = seconds
    self.wide = wide
    self.narrow = narrow
  }

  func start() {
    let link = CADisplayLink(target: self, selector: #selector(tick))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  @objc private func tick(_ link: CADisplayLink) {
    if began == 0 {
      began = link.timestamp
    }
    let progress = min(1, (link.timestamp - began) / seconds)
    // 1 at both ends, 0 halfway.
    let toward = abs(1 - 2 * progress)
    let width = narrow + (wide - narrow) * toward
    let start = CACurrentMediaTime()
    if !Self.setAppKitWidth(width) {
      #if targetEnvironment(macCatalyst)
        if let scene {
          let frame = scene.effectiveGeometry.systemFrame
          scene.requestGeometryUpdate(.Mac(systemFrame: CGRect(x: frame.minX, y: frame.minY, width: width, height: frame.height)))
        }
      #endif
    }
    steps += 1
    stepTime += (CACurrentMediaTime() - start) * 1000
    if progress >= 1 || scene == nil {
      link.invalidate()
      self.link = nil
      Shim.log(String(format: "P %.0f resized", Shim.now))
      Shim.log(String(format: "P %.0f resize_steps=%d,avg_ms=%.0f", Shim.now, steps, stepTime / Double(max(steps, 1))))
    }
  }

  /// Sets the app's AppKit window to `width`, keeping its top left corner. False without one.
  static func setAppKitWidth(_ width: Double) -> Bool {
    guard let app = (NSClassFromString("NSApplication") as? NSObject.Type)?.value(forKey: "sharedApplication") as? NSObject,
          let window = ((app.value(forKey: "windows") as? [NSObject]) ?? []).first(where: { ($0.value(forKey: "isVisible") as? Bool) == true }),
          let frame = (window.value(forKey: "frame") as? NSValue)?.cgRectValue else { return false }
    let setFrame = NSSelectorFromString("setFrame:display:")
    guard let method = class_getInstanceMethod(type(of: window), setFrame) else { return false }
    typealias SetFrame = @convention(c) (AnyObject, Selector, CGRect, Bool) -> Void
    // AppKit's origin is the bottom left, so the top stays put with the same height.
    unsafeBitCast(method_getImplementation(method), to: SetFrame.self)(window, setFrame, CGRect(x: frame.minX, y: frame.minY, width: width, height: frame.height), true)
    return true
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
      case "window" where fields.count >= 4:
        let size = CGSize(width: Double(fields[2]) ?? 0, height: Double(fields[3]) ?? 0)
        DispatchQueue.main.async { setWindow(size) }
      case "resize" where fields.count >= 5:
        let seconds = Double(fields[2]) ?? 0, narrow = Double(fields[3]) ?? 0, wide = Double(fields[4]) ?? 0
        DispatchQueue.main.async { resize(seconds: seconds, from: wide, to: narrow) }
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

  static var windowScene: UIWindowScene? {
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
  }

  /// A Mac window's size, at a fixed place on the screen, so every run lays out the same. The app
  /// comes to the front too: launched from a shell it stays behind other windows, and a covered
  /// window can stop drawing.
  static func setWindow(_ size: CGSize) {
    guard let scene = windowScene else {
      Shim.log(String(format: "P %.0f no_window", Shim.now))
      return
    }
    #if targetEnvironment(macCatalyst)
      let activate = NSSelectorFromString("activateIgnoringOtherApps:")
      if let app = (NSClassFromString("NSApplication") as? NSObject.Type)?.value(forKey: "sharedApplication") as? NSObject,
         let method = class_getInstanceMethod(type(of: app), activate)
      {
        typealias Activate = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(method_getImplementation(method), to: Activate.self)(app, activate, true)
      }
      scene.requestGeometryUpdate(.Mac(systemFrame: CGRect(origin: CGPoint(x: 40, y: 40), size: size))) { error in
        Shim.log(String(format: "P %.0f window_failed %@", Shim.now, error.localizedDescription.replacingOccurrences(of: " ", with: "_")))
      }
    #endif
    Shim.log(String(format: "P %.0f window %.0fx%.0f", Shim.now, size.width, size.height))
  }

  static func resize(seconds: Double, from wide: Double, to narrow: Double) {
    guard let scene = windowScene else {
      Shim.log(String(format: "P %.0f no_window", Shim.now))
      return
    }
    let resizer = Resizer(scene: scene, seconds: seconds, wide: wide, narrow: narrow)
    resizer.start()
    self.resizer = resizer
  }

  static var resizer: Resizer?

  /// The largest visible scroll view that can scroll vertically: the feed or the post's comments.
  static func mainScrollView() -> UIScrollView? {
    // A Mac app that isn't frontmost has no key window.
    let window = windowScene.flatMap { $0.keyWindow ?? $0.windows.first }
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
