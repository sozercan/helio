import Foundation
import Testing
@testable import HelioKit

@MainActor
struct LightBoxTimelineTests {
  private final class Feed: FeedPostsSource {
    var feedPosts: [Post]
    init(_ posts: [Post]) {
      feedPosts = posts
    }
  }

  private func post(_ id: String, image: Bool = true, over18: Bool = false) throws -> Post {
    var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(postSampleData)) as? [String: Any])
    json["id"] = id
    json["name"] = "t3_\(id)"
    json["title"] = "Post \(id)"
    json["over_18"] = over18
    json["url"] = image ? "https://i.redd.it/\(id).jpg" : "https://example.com/\(id)"
    json["domain"] = image ? "i.redd.it" : "example.com"
    json["preview"] = image ? ["images": [["source": ["url": "https://preview.redd.it/\(id).jpg", "width": 800, "height": 600]]]] : NSNull()
    let data = try JSONDecoder().decode(PostData.self, from: JSONSerialization.data(withJSONObject: json))
    return Post(data: data, contentWidth: 400, theme: defaultTheme, fetchAvatar: false, fetchLinkMetadata: false)
  }

  private func own(_ post: Post) throws -> [LightBoxPage] {
    guard case let .imgs(images)? = post.helioData?.extractedMedia else {
      Issue.record("expected an image post")
      return []
    }
    return LightBoxPost(key: "opened", title: post.data?.title).pages(images)
  }

  @Test func goesOnThroughTheFeedsOtherImagePosts() throws {
    let first = try post("a")
    let text = try post("b", image: false)
    let nsfw = try post("c", over18: true)
    let last = try post("d")
    let feed = Feed([first, text, nsfw, last])
    let blurred = CachedDefaults[.PostLinkDefSettings].blurNSFW

    let timeline = try LightBoxTimeline.around(last.helioData, in: feed, own: own(last), start: 0)
    let titles = timeline.pages.map(\.post.title)
    // No page for the text post, nor for a blurred NSFW one.
    #expect(titles == (blurred ? ["Post a", "Post d"] : ["Post a", "Post c", "Post d"]))
    #expect(timeline.pages[timeline.start].post.title == "Post d")
    #expect(timeline.pages[timeline.start].post.key == "opened")
  }

  @Test func showsOnlyItsOwnImagesOutsideTheFeed() throws {
    let listed = try post("a")
    let unlisted = try post("e")
    let pages = try own(unlisted)

    let alone = LightBoxTimeline.around(unlisted.helioData, in: Feed([listed]), own: pages, start: 0)
    #expect(alone.pages.map(\.post.title) == ["Post e"])
    let page = LightBoxTimeline.around(unlisted.helioData, in: nil, own: pages, start: 0)
    #expect(page.pages.count == 1)
    #expect(page.start == 0)
  }
}
