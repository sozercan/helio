import Foundation
import Testing
@testable import HelioKit

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

  private var theme: HelioTheme { InMemoryTheme.shared.currentTheme }

  @Test func contentWidthIsTheColumnMinusPaddingOnEveryDevice() {
    let padding = (theme.postLinks.theme.innerPadding.horizontal + theme.postLinks.theme.outerHPadding) * 2
    #expect(abs(getPostContentWidth(contentWidth: 800, theme: theme) - (800 - padding)) < 0.5)
  }

  @Test func relayoutResizesMediaForANewColumnWidth() throws {
    let post = try post()
    post.setupHelioData(contentWidth: 400, theme: theme, fetchAvatar: false)
    let narrow = try #require(post.helioData?.postDimensions)
    #expect(abs(narrow.contentWidth - getPostContentWidth(contentWidth: 400, theme: theme)) < 0.5)

    post.relayout(contentWidth: 900, theme: theme)
    let wide = try #require(post.helioData?.postDimensions)
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
    post.setupHelioData(contentWidth: 400, theme: theme, fetchAvatar: false)
    guard case .link(let before) = post.helioData?.extractedMedia else { Issue.record("expected a link"); return }

    post.relayout(contentWidth: 900, theme: theme)
    guard case .link(let after) = post.helioData?.extractedMedia else { Issue.record("expected a link"); return }
    #expect(after === before)
    #expect(post.helioData?.layoutWidth == 900)
  }

  @Test func relayoutKeepsEmbeddedReposts() throws {
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(postSampleData)) as! [String: Any]
    json["crosspost_parent_list"] = [try JSONSerialization.jsonObject(with: JSONEncoder().encode(postSampleData))]
    let data = try JSONDecoder().decode(PostData.self, from: JSONSerialization.data(withJSONObject: json))
    let post = Post(id: data.id)
    post.data = data
    post.setupHelioData(contentWidth: 400, theme: theme, fetchAvatar: false)
    guard case .repost(let before) = post.helioData?.extractedMedia else { Issue.record("expected a repost"); return }

    post.relayout(contentWidth: 900, theme: theme)
    guard case .repost(let after) = post.helioData?.extractedMedia else { Issue.record("expected a repost"); return }
    #expect(after === before)
    #expect(after.helioData?.layoutWidth == 900)
  }

  @Test func relayoutKeepsTheYouTubePlayerAndResizesItsThumbnail() throws {
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(postSampleData)) as! [String: Any]
    json["media"] = ["type": "youtube.com", "oembed": ["html": "<iframe src=\"https://www.youtube.com/embed/dQw4w9WgXcQ?feature=oembed\"></iframe>"]]
    let data = try JSONDecoder().decode(PostData.self, from: JSONSerialization.data(withJSONObject: json))
    let post = Post(id: data.id)
    post.data = data
    post.setupHelioData(contentWidth: 400, theme: theme, fetchAvatar: false)
    guard case .yt(let before) = post.helioData?.extractedMedia else { Issue.record("expected youtube"); return }

    post.relayout(contentWidth: 900, theme: theme)
    guard case .yt(let after) = post.helioData?.extractedMedia else { Issue.record("expected youtube"); return }
    #expect(after.player === before.player)
    #expect(after.thumbnailRequest.processors.map(\.identifier) != before.thumbnailRequest.processors.map(\.identifier))
  }

  @Test func relayoutForAnotherPresentationRecomputes() throws {
    let post = try post()
    post.setupHelioData(contentWidth: 400, theme: theme, fetchAvatar: false)
    post.relayout(contentWidth: 400, theme: theme, secondary: true)
    let embedded = try #require(post.helioData?.postDimensions)
    #expect(abs(embedded.contentWidth - getPostContentWidth(contentWidth: 400, secondary: true, theme: theme)) < 0.5)
  }

  @Test func imagesWithoutDimensionsIgnoreTheCachedLayout() throws {
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(postSampleData)) as! [String: Any]
    json["url"] = "https://i.redd.it/abc.jpg"
    json["preview"] = nil
    let data = try JSONDecoder().decode(PostData.self, from: JSONSerialization.data(withJSONObject: json))
    let post = Post(id: data.id)
    post.data = data
    post.setupHelioData(contentWidth: 400, theme: theme, fetchAvatar: false)
    let fresh = try #require(post.helioData?.postDimensions.mediaSize)

    // A layout capped by a short window isn't the image's shape.
    post.helioData?.postDimensions.mediaSize = CGSize(width: 1000, height: 100)
    post.relayout(contentWidth: 401, theme: theme)
    let relaid = try #require(post.helioData?.postDimensions.mediaSize)
    #expect(abs(relaid.height - (fresh.height + 1)) < 0.5)
  }

  @Test func settingUpAgainKeepsTheLastWidth() throws {
    let post = try post()
    post.setupHelioData(contentWidth: 400, theme: theme, fetchAvatar: false)
    // Refreshing a post or changing theme sets it up again without a width.
    post.setupHelioData(theme: theme, fetchAvatar: false)
    let dimensions = try #require(post.helioData?.postDimensions)
    #expect(abs(dimensions.contentWidth - getPostContentWidth(contentWidth: 400, theme: theme)) < 0.5)
  }

  @Test func relayoutAtTheSameWidthKeepsTheExistingLayout() throws {
    let post = try post()
    post.setupHelioData(contentWidth: 400, theme: theme, fetchAvatar: false)
    // A relayout would recompute the dimensions, so a cleared value shows it didn't run.
    post.helioData?.postDimensions = .zero
    post.relayout(contentWidth: 400, theme: theme)
    #expect(post.helioData?.postDimensions == .zero)
  }
}
