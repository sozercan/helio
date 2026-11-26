import Defaults

struct CommentsSectionDefSettings: Equatable, Hashable, Codable, Defaults.Serializable {
  var collapseAutoModerator: Bool = false
  var preferredSort: CommentSortOption = .confidence
  var commentSkipper: Bool = true
}
