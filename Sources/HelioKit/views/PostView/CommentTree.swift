//
//  CommentTree.swift
//  Helio
//
//  Flattens a post's comment forest into one List row per comment, "more" stub and
//  root-thread decoration. Each row renders as a single view, so the List can lay rows
//  out lazily instead of evaluating every nested comment up front, and collapsing a
//  comment only removes its descendants' rows.
//

import SwiftUI

struct CommentRow: Identifiable {
  enum Kind {
    case rootTop
    case comment(hiddenReplyCount: Int)
    /// "Load N more" stub. `parent` is nil for root-level stubs.
    case more(parent: Comment?)
    /// The "_" stub that opens the rest of a deep thread.
    case continueThread
    case rootBottom(isLastRoot: Bool)
  }

  let id: String
  let kind: Kind
  let comment: Comment
  let arrowKinds: [ArrowKind]
  let isRoot: Bool
}

enum CommentTree {
  static func rows(for roots: [Comment]) -> [CommentRow] {
    var out: [CommentRow] = []
    out.reserveCapacity(roots.count * 3)
    for (i, root) in roots.enumerated() {
      out.append(CommentRow(id: "\(root.id)-top", kind: .rootTop, comment: root, arrowKinds: [], isRoot: true))
      append(root, parent: nil, arrowKinds: [], into: &out)
      out.append(CommentRow(id: "\(root.id)-bottom", kind: .rootBottom(isLastRoot: i == roots.count - 1), comment: root, arrowKinds: [], isRoot: true))
    }
    return out
  }

  private static func append(_ comment: Comment, parent: Comment?, arrowKinds: [ArrowKind], into out: inout [CommentRow]) {
    guard let data = comment.data else { return }
    let isRoot = parent == nil

    if comment.kind == "more" {
      // Every "continue thread" stub shares the data id "_", so key it by its parent.
      // (`comment.id` has the kind appended, e.g. "_more".)
      let row = data.id == "_"
        ? CommentRow(id: "\(parent?.id ?? "root")-continue", kind: .continueThread, comment: comment, arrowKinds: arrowKinds, isRoot: isRoot)
        : CommentRow(id: comment.id, kind: .more(parent: parent), comment: comment, arrowKinds: arrowKinds, isRoot: isRoot)
      out.append(row)
      return
    }

    let children = comment.childrenHelio
    let collapsed = data.collapsed ?? false
    out.append(CommentRow(id: comment.id, kind: .comment(hiddenReplyCount: collapsed ? replyCount(children) : 0), comment: comment, arrowKinds: arrowKinds, isRoot: isRoot))
    guard !collapsed else { return }

    let childArrows = arrowKinds.map(\.child)
    for (i, child) in children.enumerated() {
      append(child, parent: comment, arrowKinds: childArrows + [i == children.count - 1 ? .curve : .straightCurve], into: &out)
    }
  }

  /// Loaded descendants plus the unloaded counts of any "more" stubs.
  static func replyCount(_ comments: [Comment]) -> Int {
    comments.reduce(0) { total, comment in
      total + (comment.kind == "more" ? (comment.data?.count ?? 0) : 1 + replyCount(comment.childrenHelio))
    }
  }
}

struct CommentTreeRowView: View {
  var row: CommentRow
  var post: Post
  var postFullname: String
  var highlightID: String?
  var seenComments: String?
  @Binding var comments: [Comment]
  @Environment(\.useTheme) private var selectedTheme

  var body: some View {
    let theme = selectedTheme.comments
    VStack(spacing: 0) {
      switch row.kind {
      case .rootTop:
        Spacer()
          .frame(maxWidth: .infinity, minHeight: theme.spacing / 2, maxHeight: theme.spacing / 2)
        Spacer()
          .frame(maxWidth: .infinity, minHeight: theme.theme.cornerRadius * 2, maxHeight: theme.theme.cornerRadius * 2, alignment: .top)
          .background(CommentBG(cornerRadius: theme.theme.cornerRadius, pos: .top).fill(theme.theme.bg()))
          .frame(maxWidth: .infinity, minHeight: theme.theme.cornerRadius, maxHeight: theme.theme.cornerRadius, alignment: .top)
          .clipped()
      case .comment(let hiddenReplyCount):
        if let helioData = row.comment.helioData {
          CommentLinkContent(highlightID: highlightID, seenComments: seenComments, arrowKinds: row.arrowKinds, post: post, comment: row.comment, helioData: helioData, hiddenReplyCount: hiddenReplyCount)
            .if(row.isRoot) { view in
              view.anchorPreference(key: CommentUtils.AnchorsKey.self, value: .center) { [row.comment.id: $0] }
            }
        }
      case .more(let parent):
        CommentLinkMore(arrowKinds: row.arrowKinds, comment: row.comment, post: post, postFullname: postFullname, parentElement: parent.map { .comment($0) } ?? .post($comments))
      case .continueThread:
        CommentLinkFull(post: post, arrowKinds: row.arrowKinds, comment: row.comment)
      case .rootBottom(let isLastRoot):
        Spacer()
          .frame(maxWidth: .infinity, minHeight: theme.theme.cornerRadius * 2, maxHeight: theme.theme.cornerRadius * 2, alignment: .top)
          .background(CommentBG(cornerRadius: theme.theme.cornerRadius, pos: .bottom).fill(theme.theme.bg()))
          .frame(maxWidth: .infinity, minHeight: theme.theme.cornerRadius, maxHeight: theme.theme.cornerRadius, alignment: .bottom)
          .clipped()
        Spacer()
          .frame(maxWidth: .infinity, minHeight: theme.spacing / 2, maxHeight: theme.spacing / 2)
        if !isLastRoot {
          NiceDivider(divider: theme.divider)
        }
      }
    }
  }
}
