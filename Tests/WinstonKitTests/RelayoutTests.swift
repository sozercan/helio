import Foundation
import Testing
@testable import WinstonKit

@MainActor
struct RelayoutTests {
  private func post() throws -> Post {
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(postSampleData)) as! [String: Any]
    json["url"] = "https://i.redd.it/abc.jpg"
    json["preview"] = ["images": [["source": ["url": "https://preview.redd.it/abc.jpg?s=sig", "width": 1000, "height": 500]]]]
    let data = try JSONDecoder().decode(PostData.self, from: JSONSerialization.data(withJSONObject: json))
    let post = Post(id: data.id)
    post.data = data
    return post
  }

  private var theme: WinstonTheme { InMemoryTheme.shared.currentTheme }

  @Test func contentWidthIsTheColumnMinusPaddingOnEveryDevice() {
    let padding = (theme.postLinks.theme.innerPadding.horizontal + theme.postLinks.theme.outerHPadding) * 2
    #expect(abs(getPostContentWidth(contentWidth: 800, theme: theme) - (800 - padding)) < 0.5)
  }

  @Test func relayoutResizesMediaForANewColumnWidth() throws {
    let post = try post()
    post.setupWinstonData(contentWidth: 400, theme: theme, fetchAvatar: false)
    let narrow = try #require(post.winstonData?.postDimensions)
    #expect(abs(narrow.contentWidth - getPostContentWidth(contentWidth: 400, theme: theme)) < 0.5)

    post.relayout(contentWidth: 900, theme: theme)
    let wide = try #require(post.winstonData?.postDimensions)
    #expect(abs(wide.contentWidth - getPostContentWidth(contentWidth: 900, theme: theme)) < 0.5)
    #expect((wide.mediaSize?.height ?? 0) > (narrow.mediaSize?.height ?? 0))
  }

  @Test func relayoutAtTheSameWidthKeepsTheExistingLayout() throws {
    let post = try post()
    post.setupWinstonData(contentWidth: 400, theme: theme, fetchAvatar: false)
    // A relayout would re-extract the media, so a cleared value shows it didn't run.
    post.winstonData?.extractedMedia = nil
    post.relayout(contentWidth: 400, theme: theme)
    #expect(post.winstonData?.extractedMedia == nil)
  }
}
