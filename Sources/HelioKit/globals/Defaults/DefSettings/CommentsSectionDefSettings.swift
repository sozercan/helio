import Defaults

enum CommentSkipperMode: String, CaseIterable, Equatable, Hashable, Codable, Defaults.Serializable, Identifiable {
  case threads
  case newComments

  var id: String {
    rawValue
  }

  var label: String {
    switch self {
    case .threads:
      "Threads"
    case .newComments:
      "New Comments"
    }
  }
}

struct CommentsSectionDefSettings: Equatable, Hashable, Codable, Defaults.Serializable {
  var collapseAutoModerator: Bool = false
  var preferredSort: CommentSortOption = .confidence
  var commentSkipper: Bool = true
  var commentSkipperMode: CommentSkipperMode = .threads

  enum CodingKeys: String, CodingKey {
    case collapseAutoModerator
    case preferredSort
    case commentSkipper
    case commentSkipperMode
  }

  init(
    collapseAutoModerator: Bool = false,
    preferredSort: CommentSortOption = .confidence,
    commentSkipper: Bool = true,
    commentSkipperMode: CommentSkipperMode = .threads,
  ) {
    self.collapseAutoModerator = collapseAutoModerator
    self.preferredSort = preferredSort
    self.commentSkipper = commentSkipper
    self.commentSkipperMode = commentSkipperMode
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    collapseAutoModerator = try container.decodeIfPresent(Bool.self, forKey: .collapseAutoModerator) ?? false
    preferredSort = try container.decodeIfPresent(CommentSortOption.self, forKey: .preferredSort) ?? .confidence
    commentSkipper = try container.decodeIfPresent(Bool.self, forKey: .commentSkipper) ?? true
    commentSkipperMode = try container.decodeIfPresent(CommentSkipperMode.self, forKey: .commentSkipperMode) ?? .threads
  }
}
