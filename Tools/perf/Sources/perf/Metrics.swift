import Foundation

/// What a benchmark run logged (see the shim): requests, periodic samples and markers.
struct RunLog {
  struct Request {
    let time: Double
    let method: String
    let url: String
  }

  struct Sample {
    let time: Double
    let values: [String: Double]
  }

  var requests: [Request] = []
  var samples: [Sample] = []
  var marks: [String: Double] = [:]
  /// Seconds since 1970 when the shim loaded, to line the log up with a trace.
  var wallClock: Double?

  init(text: String) {
    for line in text.split(separator: "\n") {
      let fields = line.split(separator: " ", maxSplits: 3).map(String.init)
      guard fields.count >= 3, let time = Double(fields[1]) else { continue }
      switch fields[0] {
      case "R" where fields.count == 4:
        requests.append(Request(time: time, method: fields[2], url: fields[3]))
      case "M":
        let pairs = line.split(separator: " ").dropFirst(2).compactMap { pair -> (String, Double)? in
          let kv = pair.split(separator: "=")
          return kv.count == 2 ? (String(kv[0]), Double(kv[1]) ?? 0) : nil
        }
        samples.append(Sample(time: time, values: Dictionary(pairs, uniquingKeysWith: { $1 })))
      case "P":
        if marks[fields[2]] == nil {
          marks[fields[2]] = time
        }
      case "W":
        wallClock = time
      default:
        break
      }
    }
  }

  /// A sampled value at a time: the last sample at or before it.
  func value(_ key: String, at time: Double) -> Double {
    (samples.last { $0.time <= time } ?? samples.first)?.values[key] ?? 0
  }
}

enum Metrics {
  /// The measured windows: scrolling Home, opening a post and scrolling its comments, everything.
  static let windows = [("feed", "scroll_start", "scroll_end"), ("post", "post_open", "cscroll_end"), ("all", "home_open", "end")]

  /// The endpoint a request went to. `image` and `link_preview` aren't Reddit API requests.
  static func category(method: String, url: String) -> String {
    let parts = URLComponents(string: url)
    let host = parts?.host?.lowercased() ?? "", path = parts?.path ?? ""
    // Reddit's web pages (link previews of a post or subreddit) aren't API requests: those go to
    // oauth.reddit.com, `/api/` or `.json`.
    let webPage = host != "oauth.reddit.com" && !path.hasPrefix("/api/") && !path.hasSuffix(".json")
    if !host.hasSuffix("reddit.com") || host.hasPrefix("i.") || host.contains("preview") || webPage {
      let media = path.range(of: #"\.(jpg|jpeg|png|gif|webp|mp4)$"#, options: .regularExpression) != nil
      return host == "fixture.local" || media || host.hasSuffix("redd.it") || host.contains("ytimg") ? "image" : "link_preview"
    }
    func matches(_ pattern: String) -> Bool {
      path.range(of: pattern, options: .regularExpression) != nil
    }
    switch true {
    case path.contains("access_token"): return "token"
    case path.hasPrefix("/api/v1/me"): return "me"
    case path.hasPrefix("/subreddits/mine"): return "subs_mine"
    case path.hasPrefix("/api/multi/mine"): return "multis"
    case path.hasPrefix("/api/info"): return "info"
    case path.hasPrefix("/api/user_data_by_account_ids"): return "avatars"
    case path.hasPrefix("/api/morechildren"): return "morechildren"
    case path.hasPrefix("/message"): return "inbox"
    case matches(#"^/r/[^/]+/about/?(\.json)?$"#): return "sub_about"
    case matches(#"^/r/[^/]+/about/"#): return "sub_rules"
    case path.contains("/comments/"): return "comments"
    case path.hasPrefix("/user/"): return "user"
    case path.contains("flair"): return "flairs"
    case method == "POST": return "post_action"
    case matches(#"^/(r/[^/]+/)?(best|hot|new|top|rising|controversial)?(\.json)?/?$"#): return "feed"
    default: return "other"
    }
  }

  /// A run's metrics, or nil when it didn't reach the end of the scenario or a deep link didn't
  /// open: its screens weren't shown, so neither their requests nor their timings count.
  static func metrics(of log: RunLog) -> [String: Double]? {
    guard let end = log.marks["end"], log.marks["open_failed"] == nil, !log.samples.isEmpty else { return nil }
    var out: [String: Double] = [:]
    for (name, start, stop) in windows {
      guard let a = log.marks[start], let b = log.marks[stop] else { continue }
      for (key, metric) in [("main", "main_ms"), ("cpu", "cpu_ms"), ("hitch", "hitch_ms"), ("hitches", "hitches")] {
        out["\(name)_\(metric)"] = log.value(key, at: b) - log.value(key, at: a)
      }
    }
    out["peak_mb"] = log.value("peak", at: end)
    out["launch_main_ms"] = log.marks["home_open"].map { log.value("main", at: $0) }
    if let open = log.marks["post_open"] {
      out["post_request_ms"] = log.requests.first { $0.url.contains("/comments/") && $0.time >= open && $0.time <= end }.map { $0.time - open } ?? -1
    }
    var counts: [String: Int] = [:]
    for request in log.requests where request.time <= end {
      counts[category(method: request.method, url: request.url), default: 0] += 1
    }
    out["link_preview_requests"] = Double(counts.removeValue(forKey: "link_preview") ?? 0)
    counts["image"] = nil
    out["reddit_requests"] = Double(counts.values.reduce(0, +))
    for (name, count) in counts {
      out["requests.\(name)"] = Double(count)
    }
    return out
  }

  struct Summary: Codable {
    var runs: [[String: Double]]
    var median: [String: Double]
  }

  static func summarize(_ label: String) -> Summary {
    let dir = Paths.label(label)
    let logs = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
      .filter { $0.hasPrefix("run") && $0.hasSuffix(".log") }.sorted()
    let runs = logs.compactMap { name in
      (try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)).flatMap { metrics(of: RunLog(text: $0)) }
    }
    guard !runs.isEmpty else { fail("no complete runs for \(label); run: perf bench \(label)") }
    let keys = Set(runs.flatMap(\.keys))
    let summary = Summary(runs: runs, median: Dictionary(uniqueKeysWithValues: keys.map { key in (key, median(runs.map { $0[key] ?? 0 })) }))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try? encoder.encode(summary).write(to: dir.appendingPathComponent("summary.json"))
    return summary
  }

  static func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    return sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
  }

  /// Timing first, then request counts.
  static func ordered(_ keys: some Collection<String>) -> [String] {
    keys.sorted { a, b in
      let (countA, countB) = (a.hasPrefix("requests."), b.hasPrefix("requests."))
      return countA == countB ? a < b : countB
    }
  }

  static func printSummary(_ label: String) {
    let summary = summarize(label)
    print("\(label): \(summary.runs.count) runs (median, then each run)")
    for key in ordered(summary.median.keys) {
      let each = summary.runs.map { String(format: "%.0f", $0[key] ?? 0) }.joined(separator: " ")
      print(pad(key, 26) + String(format: "%9.0f", summary.median[key]!) + "   [\(each)]")
    }
  }

  static func compare(_ base: String, _ new: String) {
    let a = summarize(base).median, b = summarize(new).median
    print(pad("", 26) + pad(base, 10, left: true) + pad(new, 10, left: true) + "   change")
    for key in ordered(Set(a.keys).union(b.keys)) {
      let x = a[key] ?? 0, y = b[key] ?? 0
      let change = x == 0 ? "" : String(format: "%+.0f%%", (y - x) / x * 100)
      print(pad(key, 26) + String(format: "%10.0f%10.0f", x, y) + "   \(change)")
    }
  }

  struct BudgetRow: Equatable {
    let key: String
    let value: Double
    let limit: Double
    var over: Bool {
      value > limit
    }

    var under: Bool {
      value < limit
    }
  }

  /// Compares counts with the budget. A request kind the budget doesn't list has a budget of 0.
  static func budgetRows(median: [String: Double], budget: [String: Double]) -> [BudgetRow] {
    let keys = Set(budget.keys).union(median.keys.filter { $0.hasPrefix("requests.") })
    return ordered(keys).map { BudgetRow(key: $0, value: median[$0] ?? 0, limit: budget[$0] ?? 0) }
  }

  static func check(_ label: String, budgetFile: URL) {
    guard let data = try? Data(contentsOf: budgetFile),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { fail("can't read \(budgetFile.path)") }
    let budget = object.compactMapValues { ($0 as? NSNumber)?.doubleValue }
    let median = summarize(label).median
    // Fewer requests pass, so make sure the scenario ran: Home loaded and the post asked for comments.
    guard (median["requests.feed"] ?? 0) > 0, (median["post_request_ms"] ?? -1) >= 0 else {
      fail("the benchmark didn't load Home and a post's comments; see the run logs")
    }
    let rows = budgetRows(median: median, budget: budget)
    for row in rows {
      print(pad(row.key, 24) + String(format: "%4.0f / %-4.0f  ", row.value, row.limit) + (row.over ? "over" : row.under ? "under" : "ok"))
    }
    if let summaryPath = ProcessInfo.processInfo.environment["GITHUB_STEP_SUMMARY"], let handle = FileHandle(forWritingAtPath: summaryPath) {
      handle.seekToEndOfFile()
      var text = "### Reddit requests in the perf benchmark\n\n| | Count | Budget | |\n|---|---|---|---|\n"
      for row in rows {
        text += String(format: "| `%@` | %.0f | %.0f | %@ |\n", row.key, row.value, row.limit, row.over ? "over" : row.under ? "under" : "ok")
      }
      handle.write(Data(text.utf8))
      try? handle.close()
    }
    if rows.contains(where: \.over) {
      fail("over budget. Find the extra requests in the run logs (`R` lines); if they're intended, raise Tools/perf/budget.json")
    }
    if rows.contains(where: \.under) {
      print("Under budget: lower Tools/perf/budget.json to lock the improvement in.")
    }
  }

  static func pad(_ text: String, _ width: Int, left: Bool = false) -> String {
    let padding = String(repeating: " ", count: max(0, width - text.count))
    return left ? padding + text : "  " + text + padding
  }
}
