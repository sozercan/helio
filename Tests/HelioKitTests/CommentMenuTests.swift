import Testing
@testable import HelioKit

@MainActor
struct CommentMenuTests {
  @Test func selectTextAppearsOnceInTheCommentMenu() {
    let ids = CommentLinkActions.swipeActions.map(\.id)
    #expect(!ids.contains(SelectTextCommentAction().id))
    #expect(ids.count == allCommentSwipeActions.count - 1)
  }
}
