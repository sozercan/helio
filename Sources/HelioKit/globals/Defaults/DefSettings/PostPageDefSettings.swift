import Defaults

struct PostPageDefSettings: Equatable, Hashable, Codable, Defaults.Serializable {
  var blurNSFW: Bool = false
  var preferredSearchSort: SubListingSortOption = .best
  var perPostSort: Bool = false
  var postSorts: [String: CommentSortOption] = .init()
  var showUpVoteRatio: Bool = true
}
