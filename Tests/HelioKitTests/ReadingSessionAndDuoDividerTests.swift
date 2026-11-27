import Foundation
import Testing
@testable import HelioKit

struct ReadingSessionAndDuoDividerTests {
  @Test func readingSessionRoundTripsPerAccountAndClears() throws {
    let suiteName = "helio.test.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let accountA = UUID()
    let accountB = UUID()
    ReadingSessionStore.save(feedName: "swift", accountID: accountA, defaults: defaults)
    ReadingSessionStore.save(feedName: "all", accountID: accountB, defaults: defaults)

    #expect(ReadingSessionStore.load(accountID: accountA, defaults: defaults)?.feedName == "swift")
    #expect(ReadingSessionStore.load(accountID: accountB, defaults: defaults)?.feedName == "all")

    ReadingSessionStore.clearAll(defaults: defaults)
    #expect(ReadingSessionStore.load(accountID: accountA, defaults: defaults) == nil)
    #expect(ReadingSessionStore.load(accountID: accountB, defaults: defaults) == nil)
  }

  @Test func behaviorSettingsDecodesLegacyPayloadWithRestoreOffByDefault() throws {
    let legacy = Data(#"{"openYoutubeApp":true,"preferenceDefaultFeed":"home"}"#.utf8)
    let decoded = try JSONDecoder().decode(BehaviorDefSettings.self, from: legacy)
    #expect(decoded.openYoutubeApp)
    #expect(decoded.preferenceDefaultFeed == "home")
    #expect(!decoded.restoreReadingSession)
  }

  @Test func duoDividerClampsAndSnapsToLandmarks() {
    let total: CGFloat = 1000
    #expect(DuoSplitDividerGeometry.clampedWidth(100, totalWidth: total) == DuoSplitDividerGeometry.minPaneWidth)
    #expect(DuoSplitDividerGeometry.clampedWidth(900, totalWidth: total) == total - DuoSplitDividerGeometry.minPaneWidth)

    #expect(DuoSplitDividerGeometry.snappedShare(forWidth: 504, totalWidth: total) == 0.5)
    #expect(DuoSplitDividerGeometry.snappedShare(forWidth: 403, totalWidth: total) == 0.4)
    #expect(DuoSplitDividerGeometry.snappedShare(forWidth: 598, totalWidth: total) == 0.6)
    #expect(abs(DuoSplitDividerGeometry.snappedShare(forWidth: 450, totalWidth: total) - 0.45) < 0.001)

    #expect(DuoSplitDividerGeometry.resolvedFeedWidth(savedShare: 0.4, totalWidth: 1000, defaultWidth: 500) == 400)
    #expect(DuoSplitDividerGeometry.resolvedFeedWidth(savedShare: 0.4, totalWidth: 600, defaultWidth: 300) == 300)
  }
}
