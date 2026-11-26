import Defaults

struct CommentLinkDefSettings: Equatable, Hashable, Codable, Defaults.Serializable {
  var swipeActions: SwipeActionsSet = DEFAULT_COMMENT_SWIPE_ACTIONS
  var coloredNames: Bool = false
  var jumpNextCommentButtonLeft: Bool = true
}
