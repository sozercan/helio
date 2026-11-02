import Testing
@testable import HelioKit

@MainActor
struct PostPageTitleTests {
  @Test func thePageIsTitledBySubredditWithTheCommentCount() {
    let titles = PostView.navigationTitles(postSampleData)
    #expect(titles.title == "r/Apple")
    #expect(titles.subtitle == "42 comments")
  }

  @Test func aPostStillLoadingHasNoTitle() {
    let titles = PostView.navigationTitles(nil)
    #expect(titles.title.isEmpty)
    #expect(titles.subtitle.isEmpty)
  }
}
