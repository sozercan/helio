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

  @Test func relayoutKeepsLinkPreviews() throws {
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(postSampleData)) as! [String: Any]
    json["url"] = "https://example.com/article"
    json["domain"] = "example.com"
    let data = try JSONDecoder().decode(PostData.self, from: JSONSerialization.data(withJSONObject: json))
    let post = Post(id: data.id)
    post.data = data
    post.setupWinstonData(contentWidth: 400, theme: theme, fetchAvatar: false)
    guard case .link(let before) = post.winstonData?.extractedMedia else { Issue.record("expected a link"); return }

    post.relayout(contentWidth: 900, theme: theme)
    guard case .link(let after) = post.winstonData?.extractedMedia else { Issue.record("expected a link"); return }
    #expect(after === before)
    #expect(post.winstonData?.layoutWidth == 900)
  }

  @Test func settingUpAgainKeepsTheLastWidth() throws {
    let post = try post()
    post.setupWinstonData(contentWidth: 400, theme: theme, fetchAvatar: false)
    // Refreshing a post or changing theme sets it up again without a width.
    post.setupWinstonData(theme: theme, fetchAvatar: false)
    let dimensions = try #require(post.winstonData?.postDimensions)
    #expect(abs(dimensions.contentWidth - getPostContentWidth(contentWidth: 400, theme: theme)) < 0.5)
  }

  @Test func relayoutAtTheSameWidthKeepsTheExistingLayout() throws {
    let post = try post()
    post.setupWinstonData(contentWidth: 400, theme: theme, fetchAvatar: false)
    // A relayout would recompute the dimensions, so a cleared value shows it didn't run.
    post.winstonData?.postDimensions = .zero
    post.relayout(contentWidth: 400, theme: theme)
    #expect(post.winstonData?.postDimensions == .zero)
  }
}
