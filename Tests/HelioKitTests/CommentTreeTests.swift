import Foundation
import Testing
@testable import HelioKit

private typealias RedditComment = HelioKit.Comment

@MainActor
struct CommentTreeTests {
  private func comment(_ id: String, kind: String = "t1", count: Int? = nil, collapsed: Bool = false, children: [RedditComment] = []) -> RedditComment {
    var data = CommentData(id: id)
    data.count = count
    data.collapsed = collapsed
    let comment = RedditComment(data: data, kind: kind)
    comment.childrenHelio = children
    return comment
  }

  private func labels(_ rows: [CommentRow]) -> [String] {
    rows.map { row in
      let id = row.comment.data?.id ?? "?"
      switch row.kind {
      case .rootTop: return "\(id)-top"
      case .comment: return id
      case .more: return "more:\(id)"
      case .continueThread: return "continue"
      case .rootBottom: return "\(id)-bottom"
      }
    }
  }

  @Test func flattensDepthFirstBetweenRootDecorations() {
    let roots = [
      comment("a", children: [comment("a1", children: [comment("a1x")]), comment("a2")]),
      comment("b"),
    ]
    let rows = CommentTree.rows(for: roots)
    #expect(labels(rows) == ["a-top", "a", "a1", "a1x", "a2", "a-bottom", "b-top", "b", "b-bottom"])

    guard case let .rootBottom(aIsLast) = rows[5].kind, case let .rootBottom(bIsLast) = rows[8].kind else {
      Issue.record("expected root bottom rows")
      return
    }
    #expect(!aIsLast)
    #expect(bIsLast)
    #expect(rows[1].isRoot)
    #expect(!rows[2].isRoot)
  }

  @Test func buildsThreadArrowsPerLevel() {
    let roots = [comment("a", children: [comment("a1", children: [comment("a1x")]), comment("a2", children: [comment("a2x")])])]
    let arrows = Dictionary(uniqueKeysWithValues: CommentTree.rows(for: roots).filter {
      if case .comment = $0.kind {
        true
      } else {
        false
      }
    }.map { ($0.comment.data!.id, $0.arrowKinds) })
    #expect(arrows["a"] == [])
    #expect(arrows["a1"] == [.straightCurve])
    #expect(arrows["a1x"] == [.straight, .curve])
    #expect(arrows["a2"] == [.curve])
    #expect(arrows["a2x"] == [.empty, .curve])
  }

  @Test func collapsedCommentHidesRepliesAndCountsThem() {
    let roots = [comment("a", collapsed: true, children: [
      comment("a1", children: [comment("a1x")]),
      comment("more1", kind: "more", count: 5),
    ])]
    let rows = CommentTree.rows(for: roots)
    #expect(labels(rows) == ["a-top", "a", "a-bottom"])
    guard case let .comment(hidden) = rows[1].kind else { Issue.record("expected comment row")
      return
    }
    #expect(hidden == 7)
  }

  @Test func routesMoreStubsAndKeysContinueThreadsByParent() {
    let roots = [comment("a", children: [
      comment("a1", children: [comment("_", kind: "more", count: 0)]),
      comment("a2", children: [comment("_", kind: "more", count: 0)]),
      comment("more1", kind: "more", count: 3),
    ])]
    let rows = CommentTree.rows(for: roots)
    #expect(labels(rows) == ["a-top", "a", "a1", "continue", "a2", "continue", "more:more1", "a-bottom"])
    #expect(Set(rows.map(\.id)).count == rows.count)

    guard case let .more(parent) = rows[6].kind else { Issue.record("expected more row")
      return
    }
    #expect(parent?.data?.id == "a")
    guard case .continueThread = rows[3].kind else { Issue.record("expected continue row")
      return
    }
  }
}

struct CommentDataTests {
  @Test func decodesHiddenScores() throws {
    let hidden = try JSONDecoder().decode(CommentData.self, from: Data(#"{"id":"abc","ups":1,"score_hidden":true}"#.utf8))
    #expect(hidden.score_hidden == true)
    let shown = try JSONDecoder().decode(CommentData.self, from: Data(#"{"id":"def","ups":12}"#.utf8))
    #expect(shown.score_hidden == nil)
  }

  @Test func commentJumpNavigatorFindsNewCommentsAndSkipsActiveUser() {
    var d1 = CommentData(id: "c1")
    d1.author = "alice"
    var d2 = CommentData(id: "c2")
    d2.author = "bob"
    var d3 = CommentData(id: "c3")
    d3.author = "CurrentUser"
    var d4 = CommentData(id: "c4")
    d4.author = "carol"

    let c2 = RedditComment(data: d2, kind: "t1")
    let c3 = RedditComment(data: d3, kind: "t1")
    let c1 = RedditComment(data: d1, kind: "t1")
    c1.childrenHelio = [c2, c3]
    let c4 = RedditComment(data: d4, kind: "t1")

    let targets = CommentJumpNavigator.targetIDs(
      roots: [c1, c4],
      mode: .newComments,
      seenComments: "c1",
      activeUsername: "currentuser",
    )
    #expect(targets == [c2.id, c4.id])
    #expect(CommentJumpNavigator.step(targets: targets, currentID: nil, direction: 1) == c2.id)
    #expect(CommentJumpNavigator.step(targets: targets, currentID: c2.id, direction: 1) == c4.id)
    #expect(CommentJumpNavigator.step(targets: targets, currentID: c4.id, direction: 1) == c2.id)
    #expect(CommentJumpNavigator.step(targets: targets, currentID: c2.id, direction: -1) == c4.id)

    let ordered = CommentJumpNavigator.orderedCommentIDs(roots: [c1, c4])
    #expect(ordered == [c1.id, c2.id, c3.id, c4.id])
    #expect(CommentJumpNavigator.step(targets: targets, orderedIDs: ordered, currentID: c3.id, direction: 1) == c4.id)
    #expect(CommentJumpNavigator.step(targets: targets, orderedIDs: ordered, currentID: c3.id, direction: -1) == c2.id)
  }

  @Test func commentsSectionSettingsDecodesLegacyPayloadWithDefaultJumpMode() throws {
    let legacy = Data(#"{"collapseAutoModerator":true,"commentSkipper":true}"#.utf8)
    let decoded = try JSONDecoder().decode(CommentsSectionDefSettings.self, from: legacy)
    #expect(decoded.collapseAutoModerator)
    #expect(decoded.commentSkipper)
    #expect(decoded.commentSkipperMode == .threads)
  }

  @Test func absoluteTimestampFormatsDeterministicUTCDate() throws {
    let formatted = try absoluteTimestamp(1_700_000_000, locale: Locale(identifier: "en_US_POSIX"), timeZone: #require(TimeZone(secondsFromGMT: 0)))
    #expect(formatted.contains("2023"))
    #expect(formatted.contains("Nov 14"))
  }
}
