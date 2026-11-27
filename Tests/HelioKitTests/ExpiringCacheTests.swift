import Foundation
import Testing
@testable import HelioKit

struct ExpiringCacheTests {
  @Test func storesAndRetrievesValuesBeforeExpiration() throws {
    let cache = ExpiringCache<StreamableCached>(countLimit: 10)
    let now = Date(timeIntervalSince1970: 1000)
    let value = try StreamableCached(url: #require(URL(string: "https://example.com/video.mp4")), size: CGSize(width: 640, height: 360))

    cache.set(key: "abc", value: value, expiresAt: now.addingTimeInterval(60))

    #expect(cache.get(key: "abc", now: now.addingTimeInterval(30)) == value)
  }

  @Test func evictsExpiredValuesOnRead() throws {
    let cache = ExpiringCache<StreamableCached>(countLimit: 10)
    let now = Date(timeIntervalSince1970: 1000)
    let value = try StreamableCached(url: #require(URL(string: "https://example.com/video.mp4")), size: CGSize(width: 640, height: 360))

    cache.set(key: "abc", value: value, expiresAt: now.addingTimeInterval(60))

    #expect(cache.get(key: "abc", now: now.addingTimeInterval(60)) == nil)
    #expect(cache.get(key: "abc", now: now) == nil)
  }

  @Test func removeAllClearsCachedValues() throws {
    let cache = ExpiringCache<StreamableCached>(countLimit: 10)
    let value = try StreamableCached(url: #require(URL(string: "https://example.com/video.mp4")), size: CGSize(width: 640, height: 360))

    cache.set(key: "abc", value: value)
    cache.removeAll()

    #expect(cache.get(key: "abc") == nil)
  }
}
