import Foundation

enum CommentJumpNavigator {
  static func parseSeenCommentIDs(_ seenComments: String?) -> Set<String> {
    guard let seenComments, !seenComments.isEmpty else { return [] }
    return Set(seenComments.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
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
      let seen = parseSeenCommentIDs(seenComments)
      guard !seen.isEmpty else { return [] }
      let normalizedUser = activeUsername?.lowercased()
      var results: [String] = []
      for row in CommentTree.rows(for: roots) {
        guard case .comment = row.kind, let data = row.comment.data else { continue }
        if seen.contains(data.id) {
          continue
        }
        if let normalizedUser, !normalizedUser.isEmpty, data.author?.lowercased() == normalizedUser {
          continue
        }
        results.append(row.id)
      }
      return results
    }
  }

  static func step(
    targets: [String],
    currentID: String?,
    direction: Int,
  ) -> String? {
    guard !targets.isEmpty, direction != 0 else { return nil }
    guard let currentID, let index = targets.firstIndex(of: currentID) else {
      return direction > 0 ? targets.first : targets.last
    }
    let nextIndex = (index + (direction > 0 ? 1 : -1) + targets.count) % targets.count
    return targets[nextIndex]
  }
}
