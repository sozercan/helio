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

  @Test func readingSessionTracksLatestFeedIncludingMultiAndPreservesOrdinarySubredditOnCacheMiss() throws {
    let multiData = try JSONDecoder().decode(
      MultiData.self,
      from: Data(#"{"display_name":"Tech","name":"tech","visibility":"private","path":"/user/alice/m/tech/"}"#.utf8),
    )
    let multi = Multi(data: multiData)
    let path: [Router.NavDest] = [
      .reddit(.subFeed(Subreddit(id: "home"))),
      .reddit(.post(Post(id: "p1", subID: "apple"))),
      .reddit(.multiFeed(multi)),
    ]
    #expect(ReadingSessionStore.latestFeedName(in: path) == "multi:/user/alice/m/tech/")

    let suiteName = "helio.test.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let accountID = UUID()
    ReadingSessionStore.saveCurrentFeed(in: path, accountID: accountID, defaults: defaults)
    #expect(ReadingSessionStore.load(accountID: accountID, defaults: defaults)?.feedName == "multi:/user/alice/m/tech/")

    let restoredMulti = ReadingSessionStore.destination(
      forSavedFeedName: "multi:/user/alice/m/tech/",
      accountID: accountID,
      resolveMulti: { savedPath, id in
        savedPath == "/user/alice/m/tech/" && id == accountID ? multi : nil
      },
    )
    #expect(restoredMulti == .reddit(.multiFeed(multi)))

    let builtIn = ReadingSessionStore.destination(forSavedFeedName: "feed:home")
    #expect(builtIn?.subredditFeedName == "feed:home")
    if case let .reddit(.subFeed(sub)) = builtIn {
      #expect(sub.isFeed)
    } else {
      Issue.record("expected built-in subFeed")
    }

    let ordinaryHome = ReadingSessionStore.destination(
      forSavedFeedName: "home",
      resolveSubreddit: { ReadingSessionStore.resolveOrdinarySubreddit(named: $0, lookupCached: { Subreddit(id: $0) }) },
    )
    #expect(ordinaryHome?.subredditFeedName == "home")
    if case let .reddit(.subFeed(sub)) = ordinaryHome {
      #expect(!sub.isFeed)
      #expect(sub.id == "/r/home/")
      #expect(sub.rawSubredditName == "home")
    } else {
      Issue.record("expected ordinary subFeed for r/home")
    }
  }

  @Test func splitColumnNavigationReportsFeedColumnDestinationOverPreservedPostColumn() {
    let router = Router(id: "split-feed-visit-test")
    var visited: [(String, Bool)] = []
    router.onFeedVisit = { visited.append(($0, $1)) }

    router.firstSelected = .reddit(.subFeed(Subreddit(id: "home")))
    #expect(visited.last?.0 == "feed:home")
    #expect(visited.last?.1 == true)

    router.navigateTo(.reddit(.post(Post(id: "p1", subID: "home"))), from: .feed)
    #expect(visited.last?.0 == "feed:home")
    #expect(visited.last?.1 == false)

    router.navigateTo(.reddit(.subFeed(Subreddit(id: "apple"))), from: .post)
    #expect(visited.last?.0 == "apple")
    #expect(visited.last?.1 == true)

    router.navigateTo(.reddit(.subFeed(Subreddit(id: "swift"))), from: .feed)
    #expect(visited.last?.0 == "swift")
    #expect(visited.last?.1 == true)

    router.firstSelected = .reddit(.subFeed(Subreddit(id: "pics")))
    #expect(visited.last?.0 == "pics")
    #expect(visited.last?.1 == true)

    router.showFeedRoot(.reddit(.subFeed(Subreddit(id: "news"))))
    #expect(visited.last?.0 == "news")
    #expect(visited.last?.1 == true)

    router.navigateTo(.reddit(.post(Post(id: "p2", subID: "news"))), from: .feed)
    #expect(visited.last?.0 == "news")
    #expect(visited.last?.1 == false)

    router.goBack()
    #expect(visited.last?.1 == false)
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
    #expect(DuoSplitDividerGeometry.resolvedFeedWidth(savedShare: nil, totalWidth: 654, defaultWidth: 327) == 320)
    #expect(!DuoSplitDividerGeometry.canResize(totalWidth: DuoSplitDividerGeometry.minPaneWidth * 2))
    #expect(DuoSplitDividerGeometry.canResize(totalWidth: DuoSplitDividerGeometry.minPaneWidth * 2 + DuoSplitDividerGeometry.dividerWidth))
  }

  @Test func duoDividerDragOffsetClampsWithinPaneBounds() {
    let total: CGFloat = 1000 + DuoSplitDividerGeometry.dividerWidth
    let minWidth = DuoSplitDividerGeometry.minPaneWidth
    let maxWidth = 1000 - minWidth

    #expect(DuoSplitDividerGeometry.dragOffset(forBaseWidth: 500, translation: 75, totalWidth: total) == 75)
    #expect(DuoSplitDividerGeometry.dragOffset(forBaseWidth: 500, translation: -500, totalWidth: total) == minWidth - 500)
    #expect(DuoSplitDividerGeometry.dragOffset(forBaseWidth: 500, translation: 500, totalWidth: total) == maxWidth - 500)
    #expect(DuoSplitDividerGeometry.dragOffset(forBaseWidth: 100, translation: 0, totalWidth: total) == 0)
  }
}
