import Foundation

enum CommentJumpNavigator {
  static func parseSeenCommentIDs(_ seenComments: String?) -> Set<String> {
    guard let seenComments, !seenComments.isEmpty else { return [] }
    return Set(seenComments.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
  }

  static func orderedCommentIDs(roots: [Comment]) -> [String] {
    var out: [String] = []
    for root in roots {
      appendVisibleIDs(root, into: &out)
    }
    return out
  }

  private static func appendVisibleIDs(_ comment: Comment, into out: inout [String]) {
    guard let data = comment.data, comment.kind != "more" else { return }
    out.append(comment.id)
    guard !(data.collapsed ?? false) else { return }
    for child in comment.childrenHelio {
      appendVisibleIDs(child, into: &out)
    }
  }

  static func targetIDs(
    roots: [Comment],
    mode: CommentSkipperMode,
    seenComments: String?,
    activeUsername: String?,
  ) -> [String] {
    switch mode {
    case .threads:
      return roots.map(\.id)
    case .newComments:
      guard let seenComments else { return [] }
      let seen = parseSeenCommentIDs(seenComments)
      let normalizedUser = activeUsername?.lowercased()
      var results: [String] = []
      for root in roots {
        appendNewCommentIDs(root, seen: seen, activeUsername: normalizedUser, into: &results)
      }
      return results
    }
  }

  private static func appendNewCommentIDs(
    _ comment: Comment,
    seen: Set<String>,
    activeUsername: String?,
    into results: inout [String],
  ) {
    guard let data = comment.data, comment.kind != "more" else { return }
    let isOwn = if let activeUsername, !activeUsername.isEmpty {
      data.author?.lowercased() == activeUsername
    } else {
      false
    }
    if !seen.contains(data.id), !isOwn {
      results.append(comment.id)
    }
    guard !(data.collapsed ?? false) else { return }
    for child in comment.childrenHelio {
      appendNewCommentIDs(child, seen: seen, activeUsername: activeUsername, into: &results)
    }
  }

  static func step(
    targets: [String],
    orderedIDs: [String] = [],
    currentID: String?,
    direction: Int,
  ) -> String? {
    guard !targets.isEmpty, direction != 0 else { return nil }
    if let currentID, let index = targets.firstIndex(of: currentID) {
      let nextIndex = (index + (direction > 0 ? 1 : -1) + targets.count) % targets.count
      return targets[nextIndex]
    }
    if let currentID, !orderedIDs.isEmpty, let currentPos = orderedIDs.firstIndex(of: currentID) {
      let positions = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { ($0.element, $0.offset) })
      if direction > 0 {
        if let next = targets.first(where: { (positions[$0] ?? -1) > currentPos }) {
          return next
        }
        return targets.first
      } else {
        if let prev = targets.last(where: { (positions[$0] ?? Int.max) < currentPos }) {
          return prev
        }
        return targets.last
      }
    }
    return direction > 0 ? targets.first : targets.last
  }
}
