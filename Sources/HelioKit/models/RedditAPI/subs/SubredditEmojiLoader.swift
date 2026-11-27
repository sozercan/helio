import Foundation
import Nuke

struct FlairEmoji: Decodable, Sendable, Equatable {
  let url: String
}

enum FlairSegment: Equatable, Hashable, Sendable {
  case text(String)
  case emoji(String)
}

enum FlairParser {
  private static let emojiTokenRegex = try? NSRegularExpression(pattern: ":([A-Za-z0-9_+-]+):")

  static func parse(_ raw: String?) -> [FlairSegment] {
    guard let raw, !raw.isEmpty else { return [] }
    guard let regex = emojiTokenRegex else {
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? [] : [.text(trimmed)]
    }

    let ns = raw as NSString
    let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
    if matches.isEmpty {
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? [] : [.text(trimmed)]
    }

    var segments: [FlairSegment] = []
    var cursor = 0
    for match in matches {
      if match.range.location > cursor {
        let prefix = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
          .trimmingCharacters(in: .whitespacesAndNewlines)
        if !prefix.isEmpty {
          segments.append(.text(prefix))
        }
      }
      let emojiName = ns.substring(with: match.range(at: 1))
      if !emojiName.isEmpty {
        segments.append(.emoji(emojiName))
      }
      cursor = match.range.location + match.range.length
    }

    if cursor < ns.length {
      let suffix = ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !suffix.isEmpty {
        segments.append(.text(suffix))
      }
    }

    return segments
  }

  static func emojiNames(in raw: String?) -> [String] {
    parse(raw).compactMap { segment in
      if case let .emoji(name) = segment {
        return name
      }
      return nil
    }
  }

  static func containsEmojiTokens(_ raw: String?) -> Bool {
    !emojiNames(in: raw).isEmpty
  }
}

actor SubredditEmojiLoader {
  static let shared = SubredditEmojiLoader()
  static let maxAge: TimeInterval = 30 * 60

  typealias Fetch = @Sendable (_ subreddit: String, _ account: RedditCredential) async -> [String: URL]?

  private let fetch: Fetch
  private let currentAccount: @Sendable () async -> RedditCredential?
  private var cache: [String: (emojis: [String: URL], date: Date)] = [:]
  private var inFlight: [String: Task<[String: URL]?, Never>] = [:]

  init(
    currentAccount: @escaping @Sendable () async -> RedditCredential? = {
      await MainActor.run { RedditCredentialsManager.shared.selectedCredential }
    },
    fetch: @escaping Fetch = { subreddit, account in
      guard !RedditRateLimit.shared.isLow(account: account.id, authorization: account.authorizationID) else { return nil }
      return await RedditAPI.shared.fetchSubredditEmojis(subreddit, altCredential: account)
    },
  ) {
    self.currentAccount = currentAccount
    self.fetch = fetch
  }

  func cachedEmojiURLs(for subreddit: String) -> [String: URL]? {
    let key = Self.normalize(subreddit)
    guard !key.isEmpty, let entry = cache[key], Date().timeIntervalSince(entry.date) < Self.maxAge else {
      return nil
    }
    return entry.emojis
  }

  func emojiURLs(for subreddit: String) async -> [String: URL] {
    let key = Self.normalize(subreddit)
    guard !key.isEmpty else { return [:] }
    if let entry = cache[key], Date().timeIntervalSince(entry.date) < Self.maxAge {
      return entry.emojis
    }
    if let existing = inFlight[key] {
      return await existing.value ?? [:]
    }
    let task = Task<[String: URL]?, Never> { [currentAccount, fetch] in
      guard let account = await currentAccount() else { return nil }
      return await fetch(key, account)
    }
    inFlight[key] = task
    let fetched = await task.value
    inFlight[key] = nil
    if let fetched {
      cache[key] = (fetched, Date())
      return fetched
    }
    return [:]
  }

  static func normalize(_ subreddit: String) -> String {
    let trimmed = subreddit.trimmingCharacters(in: .whitespacesAndNewlines)
    let stripped = trimmed.lowercased().hasPrefix("r/") ? String(trimmed.dropFirst(2)) : trimmed
    return stripped.lowercased()
  }

  static func decodeEmojis(from data: Data) -> [String: URL]? {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }
    var urls: [String: URL] = [:]
    for (_, groupValue) in root {
      guard let group = groupValue as? [String: Any] else { continue }
      for (name, emojiValue) in group {
        guard let emojiDict = emojiValue as? [String: Any],
              let urlString = emojiDict["url"] as? String,
              let url = URL(string: urlString),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else { continue }
        urls[name] = url
        urls[name.lowercased()] = url
      }
    }
    return urls
  }
}

extension RedditAPI {
  func fetchSubredditEmojis(_ subreddit: String, altCredential: RedditCredential? = nil) async -> [String: URL]? {
    let normalized = SubredditEmojiLoader.normalize(subreddit)
    guard !normalized.isEmpty,
          let encoded = normalized.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    else { return nil }
    let url = "\(RedditAPI.redditApiURLBase)/api/v1/\(encoded)/emojis/all"
    switch await self.doRequest(url, method: .get, decodable: SubredditEmojisResponse.self, altCredential: altCredential) {
    case let .success(response):
      return response.urls
    case .failure:
      return nil
    }
  }

  struct SubredditEmojisResponse: Decodable {
    let urls: [String: URL]

    private struct DynamicCodingKey: CodingKey {
      var stringValue: String
      var intValue: Int?

      init?(stringValue: String) {
        self.stringValue = stringValue
      }

      init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
      }
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: DynamicCodingKey.self)
      var collected: [String: URL] = [:]
      for groupKey in container.allKeys {
        guard let group = try? container.decode([String: FlairEmoji].self, forKey: groupKey) else { continue }
        for (name, emoji) in group {
          guard let url = URL(string: emoji.url),
                ["http", "https"].contains(url.scheme?.lowercased() ?? "")
          else { continue }
          collected[name] = url
          collected[name.lowercased()] = url
        }
      }
      self.urls = collected
    }
  }
}
