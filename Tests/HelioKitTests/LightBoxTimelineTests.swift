import Foundation
import Testing
@testable import HelioKit

@MainActor
struct LightBoxTimelineTests {
  private final class Feed: FeedPostsSource {
    var feedPosts: [Post]
    var revealed: [String] = []
    init(_ posts: [Post]) {
      feedPosts = posts
    }

    func reveal(_ postID: String) {
      revealed.append(postID)
    }
  }

  private func post(_ id: String, image: Bool = true, video: Bool = false, over18: Bool = false) throws -> Post {
    var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(postSampleData)) as? [String: Any])
    json["id"] = id
    json["name"] = "t3_\(id)"
    json["title"] = "Post \(id)"
    json["over_18"] = over18
    json["url"] = image ? "https://i.redd.it/\(id).jpg" : "https://example.com/\(id)"
    json["domain"] = image ? "i.redd.it" : "example.com"
    json["preview"] = image ? ["images": [["source": ["url": "https://preview.redd.it/\(id).jpg", "width": 800, "height": 600]]]] : NSNull()
    if video {
      json["url"] = "https://v.redd.it/\(id)"
      json["domain"] = "v.redd.it"
      json["preview"] = ["reddit_video_preview": ["hls_url": "https://v.redd.it/\(id)/HLSPlaylist.m3u8", "width": 640, "height": 360]]
    }
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
    // Each page knows its post in the feed, the opened one too, to scroll the feed to.
    #expect(timeline.pages.map(\.post.feedID) == (blurred ? ["a", "d"] : ["a", "c", "d"]))
    timeline.reveal?("a")
    #expect(feed.revealed == ["a"])
  }

  @Test func goesOnToTheFeedsVideosToo() throws {
    let image = try post("a")
    let video = try post("v", image: false, video: true)
    let timeline = try LightBoxTimeline.around(image.helioData, in: Feed([image, video]), own: own(image), start: 0)
    #expect(timeline.pages.map(\.post.title) == ["Post a", "Post v"])
    guard case let .video(shared, holder) = timeline.pages[1].media else {
      Issue.record("expected a video page")
      return
    }
    #expect(shared.url.absoluteString == "https://v.redd.it/v/HLSPlaylist.m3u8")
    // Another post's video gets a player of its own in the lightbox.
    #expect(holder == nil)
    #expect(timeline.pages[1].media.isScrubbable)
    #expect(!timeline.pages[0].media.isScrubbable)
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
