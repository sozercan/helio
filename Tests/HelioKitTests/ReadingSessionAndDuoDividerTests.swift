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
    ReadingSessionStore.save(feedName: "feed:all", accountID: accountB, defaults: defaults)

    #expect(ReadingSessionStore.load(accountID: accountA, defaults: defaults)?.feedName == "swift")
    #expect(ReadingSessionStore.load(accountID: accountB, defaults: defaults)?.feedName == "feed:all")

    ReadingSessionStore.clearAll(defaults: defaults)
    #expect(ReadingSessionStore.load(accountID: accountA, defaults: defaults) == nil)
    #expect(ReadingSessionStore.load(accountID: accountB, defaults: defaults) == nil)
  }

  @Test func readingSessionTracksLatestSubredditInPathAndDecodesBuiltInPrefix() {
    let path: [Router.NavDest] = [
      .reddit(.subFeed(Subreddit(id: "home"))),
      .reddit(.post(Post(id: "p1", subID: "apple"))),
      .reddit(.subFeed(Subreddit(id: "apple"))),
    ]
    #expect(ReadingSessionStore.latestFeedName(in: path) == "apple")

    let builtIn = ReadingSessionStore.destination(forSavedFeedName: "feed:home") { Subreddit(id: "sub:\($0)") }
    #expect(builtIn?.subredditFeedName == "feed:home")

    let ordinaryHome = ReadingSessionStore.destination(forSavedFeedName: "home") { Subreddit(id: "sub:\($0)") }
    #expect(ordinaryHome?.subredditFeedName == "sub:home")
  }

  @Test func behaviorSettingsDecodesLegacyPayloadWithRestoreOffByDefault() throws {
    let legacy = Data(#"{"openYoutubeApp":true,"preferenceDefaultFeed":"home"}"#.utf8)
    let decoded = try JSONDecoder().decode(BehaviorDefSettings.self, from: legacy)
    #expect(decoded.openYoutubeApp)
    #expect(decoded.preferenceDefaultFeed == "home")
    #expect(!decoded.restoreReadingSession)
  }

  @Test func duoDividerExcludesDividerWidthWhenClampingAndSnapping() {
    let total: CGFloat = 1000 + DuoSplitDividerGeometry.dividerWidth
    let available = DuoSplitDividerGeometry.availablePaneWidth(totalWidth: total)
    #expect(available == 1000)

    #expect(DuoSplitDividerGeometry.clampedWidth(100, totalWidth: total) == DuoSplitDividerGeometry.minPaneWidth)
    #expect(DuoSplitDividerGeometry.clampedWidth(900, totalWidth: total) == available - DuoSplitDividerGeometry.minPaneWidth)

    #expect(DuoSplitDividerGeometry.snappedShare(forWidth: 504, totalWidth: total) == 0.5)
    #expect(DuoSplitDividerGeometry.snappedShare(forWidth: 403, totalWidth: total) == 0.4)
    #expect(DuoSplitDividerGeometry.snappedShare(forWidth: 598, totalWidth: total) == 0.6)
    #expect(abs(DuoSplitDividerGeometry.snappedShare(forWidth: 450, totalWidth: total) - 0.45) < 0.001)

    #expect(DuoSplitDividerGeometry.resolvedFeedWidth(savedShare: 0.5, totalWidth: total, defaultWidth: 400) == 500)
    #expect(!DuoSplitDividerGeometry.canResize(totalWidth: DuoSplitDividerGeometry.minPaneWidth * 2))
    #expect(DuoSplitDividerGeometry.canResize(totalWidth: DuoSplitDividerGeometry.minPaneWidth * 2 + DuoSplitDividerGeometry.dividerWidth))
  }
}
