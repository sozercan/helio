import Alamofire
import Foundation
import Synchronization
import Testing
@testable import HelioKit

/// Records the batches a loader sends.
private final class Calls: Sendable {
  private let batches = Mutex<[[String]]>([])

  func record(_ batch: [String]) {
    batches.withLock { $0.append(batch.sorted()) }
  }

  var all: [[String]] {
    batches.withLock { $0 }
  }
}

struct AvatarLoaderTests {
  @Test func coalescesConcurrentLookupsIntoOneRequest() async {
    let calls = Calls()
    let loader = AvatarLoader { ids in
      calls.record(ids)
      return Dictionary(uniqueKeysWithValues: ids.map { ($0, "https://example.com/\($0).png?width=256") })
    }
    async let first = loader.avatarURLs(for: ["t2_a", "t2_b"])
    async let second = loader.avatarURLs(for: ["t2_b", "t2_c"])
    let (a, b) = await (first, second)

    #expect(calls.all == [["t2_a", "t2_b", "t2_c"]])
    #expect(a["t2_a"]?.absoluteString == "https://example.com/t2_a.png")
    #expect(b.keys.sorted() == ["t2_b", "t2_c"])
  }

  @Test func asksOnceForEachAuthor() async {
    let calls = Calls()
    let loader = AvatarLoader { ids in
      calls.record(ids)
      return Dictionary(uniqueKeysWithValues: ids.map { ($0, $0 == "t2_none" ? nil : "https://example.com/\($0).png") })
    }
    _ = await loader.avatarURLs(for: ["t2_a", "t2_none"])
    let again = await loader.avatarURLs(for: ["t2_a", "t2_none", "t2_new"])

    #expect(calls.all == [["t2_a", "t2_none"], ["t2_new"]])
    #expect(again.keys.sorted() == ["t2_a", "t2_new"])
  }

  @Test func splitsLargeLookupsIntoBatches() async {
    let calls = Calls()
    let loader = AvatarLoader { ids in
      calls.record(ids)
      return [:]
    }
    _ = await loader.avatarURLs(for: (0 ..< 250).map { "t2_\($0)" })

    #expect(calls.all.map(\.count).sorted() == [50, 100, 100])
  }

  @Test func asksAgainAfterAFailedRequest() async {
    let calls = Calls()
    let loader = AvatarLoader { ids in
      calls.record(ids)
      return calls.all.count == 1 ? nil : ["t2_a": "https://example.com/a.png"]
    }
    #expect(await loader.avatarURLs(for: ["t2_a"]).isEmpty)
    #expect(await loader.avatarURLs(for: ["t2_a"])["t2_a"] != nil)
    #expect(calls.all.count == 2)
  }
}

struct RedditInfoLoaderTests {
  private func post(_ id: String) -> PostData? {
    guard var json = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(postSampleData))) as? [String: Any] else { return nil }
    json["id"] = id
    json["name"] = "t3_\(id)"
    return try? JSONDecoder().decode(PostData.self, from: JSONSerialization.data(withJSONObject: json))
  }

  private func subreddit(_ name: String) -> SubredditData? {
    let json: [String: Any] = ["id": "2qh1f", "name": "t5_2qh1f", "display_name": name, "public_description": "", "url": "/r/\(name)/"]
    return try? JSONDecoder().decode(SubredditData.self, from: JSONSerialization.data(withJSONObject: json))
  }

  @Test func batchesPostsAndSubredditsAndCachesThem() async {
    let calls = Calls()
    let loader = RedditInfoLoader { fullnames, names in
      calls.record(fullnames + names.map { "sr:\($0)" })
      var things = fullnames.compactMap { self.post(String($0.dropFirst(3))).map(RedditInfoLoader.Thing.post) }
      if names.contains("apple"), let apple = self.subreddit("apple") {
        things.append(.subreddit(apple))
      }
      return things
    }
    async let a = loader.post("t3_a")
    async let b = loader.post("t3_b")
    async let sub = loader.subreddit(named: "Apple")
    let (postA, postB, apple) = await (a, b, sub)
    let again = await loader.post("t3_a")

    #expect(postA?.id == "a")
    #expect(postB?.id == "b")
    #expect(apple?.display_name == "apple")
    #expect(again?.id == "a")
    #expect(calls.all.sorted { $0.count > $1.count } == [["t3_a", "t3_b"], ["sr:apple"]])
  }
}

struct LinkMetadataLoaderTests {
  @Test func downloadsEachPageOnce() async throws {
    let calls = Calls()
    let loader = LinkMetadataLoader { url in
      calls.record([url.absoluteString])
      try? await Task.sleep(for: .milliseconds(20))
      return .init(title: "Title", description: nil, image: nil, url: nil)
    }
    let url = try #require(URL(string: "https://example.com/article"))
    async let first = loader.metadata(for: url)
    async let second = loader.metadata(for: url)
    _ = await (first, second)
    let third = await loader.metadata(for: url)

    #expect(third?.title == "Title")
    #expect(calls.all.count == 1)
  }
}

struct AccessTokenRefresherTests {
  private func token(_ value: String, age: TimeInterval = 0) -> RedditCredential.AccessToken {
    .init(token: value, expiration: 3600, lastRefresh: Date().addingTimeInterval(-age))
  }

  @Test func concurrentRefreshesShareOneRequest() async {
    let calls = Calls()
    let refresher = AccessTokenRefresher()
    let refresh: @Sendable () async -> RedditCredential.AccessToken? = {
      calls.record(["refresh"])
      try? await Task.sleep(for: .milliseconds(20))
      return self.token("new")
    }
    async let a = refresher.token(refreshToken: "r", forceRenew: false, refresh: refresh)
    async let b = refresher.token(refreshToken: "r", forceRenew: false, refresh: refresh)
    let (first, second) = await (a, b)
    // Asked again before the credential stored the new token.
    let third = await refresher.token(refreshToken: "r", forceRenew: false, refresh: refresh)

    #expect(first?.token == "new" && second?.token == "new" && third?.token == "new")
    #expect(calls.all.count == 1)
  }

  @Test func forcedRenewalRefreshesAStaleToken() async {
    let calls = Calls()
    let refresher = AccessTokenRefresher()
    _ = await refresher.token(refreshToken: "r", forceRenew: false) {
      calls.record(["first"])
      return self.token("old", age: AccessTokenRefresher.forcedReuseWindow + 1)
    }
    let renewed = await refresher.token(refreshToken: "r", forceRenew: true) {
      calls.record(["second"])
      return self.token("new")
    }

    #expect(renewed?.token == "new")
    #expect(calls.all.count == 2)
  }
}

struct RetryPolicyTests {
  @Test func retriesOnlyFailuresThatCanSucceedLater() {
    func status(_ code: Int) -> AFError {
      .responseValidationFailed(reason: .unacceptableStatusCode(code: code))
    }
    #expect(RedditAPI.isTransient(status(503)))
    #expect(RedditAPI.isTransient(.sessionTaskFailed(error: URLError(.networkConnectionLost))))
    #expect(!RedditAPI.isTransient(status(404)))
    #expect(!RedditAPI.isTransient(status(403)))
    #expect(!RedditAPI.isTransient(status(429)))
    #expect(!RedditAPI.isTransient(.responseSerializationFailed(reason: .inputDataNilOrZeroLength)))
    #expect(!RedditAPI.isTransient(.explicitlyCancelled))
  }
}
