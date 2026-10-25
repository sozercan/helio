import Foundation
import Testing
@testable import winston

/// Swift Testing also declares a `Comment` type.
private typealias RedditComment = winston.Comment

@MainActor
struct CommentTreeTests {
  private func comment(_ id: String, kind: String = "t1", count: Int? = nil, collapsed: Bool = false, children: [RedditComment] = []) -> RedditComment {
    var data = CommentData(id: id)
    data.count = count
    data.collapsed = collapsed
    let comment = RedditComment(data: data, kind: kind)
    comment.childrenWinston = children
    return comment
  }

  /// Rows as readable labels keyed by the comments' data ids (entity ids have the kind appended).
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

    guard case .rootBottom(let aIsLast) = rows[5].kind, case .rootBottom(let bIsLast) = rows[8].kind else {
      Issue.record("expected root bottom rows"); return
    }
    #expect(!aIsLast)
    #expect(bIsLast)
    #expect(rows[1].isRoot)
    #expect(!rows[2].isRoot)
  }

  @Test func buildsThreadArrowsPerLevel() {
    let roots = [comment("a", children: [comment("a1", children: [comment("a1x")]), comment("a2", children: [comment("a2x")])])]
    let arrows = Dictionary(uniqueKeysWithValues: CommentTree.rows(for: roots).filter { if case .comment = $0.kind { true } else { false } }.map { ($0.comment.data!.id, $0.arrowKinds) })
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
    guard case .comment(let hidden) = rows[1].kind else { Issue.record("expected comment row"); return }
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

    guard case .more(let parent) = rows[6].kind else { Issue.record("expected more row"); return }
    #expect(parent?.data?.id == "a")
    guard case .continueThread = rows[3].kind else { Issue.record("expected continue row"); return }
  }
}

struct CommentDataTests {
  @Test func decodesHiddenScores() throws {
    let hidden = try JSONDecoder().decode(CommentData.self, from: Data(#"{"id":"abc","ups":1,"score_hidden":true}"#.utf8))
    #expect(hidden.score_hidden == true)
    let shown = try JSONDecoder().decode(CommentData.self, from: Data(#"{"id":"def","ups":12}"#.utf8))
    #expect(shown.score_hidden == nil)
  }
}
