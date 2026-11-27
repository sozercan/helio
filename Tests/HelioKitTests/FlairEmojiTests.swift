import Foundation
import Synchronization
import Testing
@testable import HelioKit

private final class EmojiFetchCounter: Sendable {
  private let subreddits = Mutex<[String]>([])

  func record(_ subreddit: String) {
    subreddits.withLock { $0.append(subreddit) }
  }

  var all: [String] {
    subreddits.withLock { $0 }
  }
}

struct FlairEmojiTests {
  @Test func parsesTextAndEmojiSegmentsInOrder() {
    let segments = FlairParser.parse(":apple: iPhone 16 Pro :rocket:")
    #expect(segments == [.emoji("apple"), .text("iPhone 16 Pro"), .emoji("rocket")])
    #expect(FlairParser.emojiNames(in: ":apple: iPhone 16 Pro :rocket:") == ["apple", "rocket"])
    #expect(FlairParser.containsEmojiTokens(":apple: iPhone 16 Pro :rocket:"))
  }

  @Test func parsesPlainTextWithoutEmojiTokens() {
    #expect(FlairParser.parse("Moderator") == [.text("Moderator")])
    #expect(FlairParser.emojiNames(in: "Moderator").isEmpty)
    #expect(!FlairParser.containsEmojiTokens("Moderator"))
    #expect(FlairParser.parse(nil).isEmpty)
    #expect(FlairParser.parse("   ").isEmpty)
  }

  @Test func preservesFallbackStrippingForPlainFlairHelpers() {
    #expect(flairWithoutEmojis(str: ":star: VIP :rocket:") == ["VIP"])
    #expect(flairWithoutEmojis(str: ":only_emoji:") == [])
    #expect(flairWithoutEmojis(str: nil) == nil)
  }

  @Test func decodesSubredditEmojisResponsePayload() throws {
    let json = """
    {
      "snoovatar": {
        "snoo": { "url": "https://emoji.redditmedia.com/snoo.png" }
      },
      "t5_2qh1f": {
        "AppleLogo": { "url": "https://emoji.redditmedia.com/apple.png" },
        "invalid": { "url": "javascript:alert(1)" }
      }
    }
    """
    let decoded = try JSONDecoder().decode(RedditAPI.SubredditEmojisResponse.self, from: Data(json.utf8))
    #expect(decoded.urls["snoo"]?.absoluteString == "https://emoji.redditmedia.com/snoo.png")
    #expect(decoded.urls["AppleLogo"]?.absoluteString == "https://emoji.redditmedia.com/apple.png")
    #expect(decoded.urls["applelogo"]?.absoluteString == "https://emoji.redditmedia.com/apple.png")
    #expect(decoded.urls["invalid"] == nil)
  }

  @Test func cachesAndDeduplicatesConcurrentEmojiFetchesPerSubreddit() async {
    let counter = EmojiFetchCounter()
    let account = RedditCredential(apiAppID: "placeholder-client-id", refreshToken: "placeholder-refresh-token")
    let loader = SubredditEmojiLoader(currentAccount: { account }, fetch: { subreddit, _ in
      counter.record(subreddit)
      try? await Task.sleep(for: .milliseconds(30))
      return ["apple": URL(string: "https://emoji.redditmedia.com/\(subreddit)/apple.png")!]
    })

    async let first = loader.emojiURLs(for: "Apple")
    async let second = loader.emojiURLs(for: "r/apple")
    let (a, b) = await (first, second)
    let third = await loader.emojiURLs(for: "APPLE")

    #expect(counter.all == ["apple"])
    #expect(a["apple"]?.absoluteString == "https://emoji.redditmedia.com/apple/apple.png")
    #expect(b == a)
    #expect(third == a)
    #expect(await loader.cachedEmojiURLs(for: "apple") == a)
  }

  @Test func returnsEmptyWithoutNetworkWhenUnauthenticated() async {
    let counter = EmojiFetchCounter()
    let loader = SubredditEmojiLoader(currentAccount: { nil }, fetch: { subreddit, _ in
      counter.record(subreddit)
      return ["apple": URL(string: "https://emoji.redditmedia.com/apple.png")!]
    })

    let result = await loader.emojiURLs(for: "apple")
    #expect(result.isEmpty)
    #expect(counter.all.isEmpty)
  }

  @Test func backsOffAndRetriesAfterFailedEmojiFetch() async {
    let counter = EmojiFetchCounter()
    let account = RedditCredential(apiAppID: "placeholder-client-id", refreshToken: "placeholder-refresh-token")
    let loader = SubredditEmojiLoader(currentAccount: { account }, failureBackoff: 60, fetch: { subreddit, _ in
      counter.record(subreddit)
      if counter.all.count == 1 {
        return nil
      }
      return ["star": URL(string: "https://emoji.redditmedia.com/star.png")!]
    })

    let t0 = Date(timeIntervalSince1970: 1_000)
    let first = await loader.emojiURLs(for: "swift", now: t0)
    let duringBackoff = await loader.emojiURLs(for: "swift", now: t0.addingTimeInterval(30))
    let afterBackoff = await loader.emojiURLs(for: "swift", now: t0.addingTimeInterval(61))
    #expect(first.isEmpty)
    #expect(duringBackoff.isEmpty)
    #expect(afterBackoff["star"]?.absoluteString == "https://emoji.redditmedia.com/star.png")
    #expect(counter.all == ["swift", "swift"])
  }
}
