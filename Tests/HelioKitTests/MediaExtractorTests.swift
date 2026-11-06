import Foundation
import Nuke
import Testing
import UIKit
@testable import HelioKit

struct MediaExtractorTests {
  /// The sample post re-keyed with Reddit-shaped JSON overrides.
  private func postData(_ overrides: [String: Any]) throws -> PostData {
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(postSampleData)) as! [String: Any]
    json["url"] = "https://example.com/article"
    json["domain"] = "example.com"
    json.merge(overrides) { $1 }
    return try JSONDecoder().decode(PostData.self, from: JSONSerialization.data(withJSONObject: json))
  }

  private func extract(_ overrides: [String: Any]) throws -> MediaExtractedType? {
    try mediaExtractor(compact: false, contentWidth: 400, postData(overrides))
  }

  @Test func showsCrosspostsAsTheOriginalPostEvenWithVideoMedia() throws {
    let original = try JSONSerialization.jsonObject(with: JSONEncoder().encode(postSampleData))
    let result = try extract([
      "url": "https://v.redd.it/abc123",
      "preview": ["reddit_video_preview": ["hls_url": "https://v.redd.it/abc123/HLSPlaylist.m3u8", "width": 640, "height": 360]],
      "crosspost_parent_list": [original],
    ])
    guard case .repost = result else { Issue.record("expected repost, got \(String(describing: result))")
      return
    }
  }

  @Test func sizesASingleImageToItsWidthAndOneOfUnknownSizeToFillItsSquare() throws {
    func resize(_ preview: Any?) throws -> String? {
      var overrides: [String: Any] = ["url": "https://i.redd.it/abc.jpg", "domain": "i.redd.it"]
      overrides["preview"] = preview ?? NSNull()
      guard case let .imgs(images)? = try extract(overrides) else { return nil }
      return images.first?.request.processors.first?.identifier
    }
    let known = ["images": [["source": ["url": "https://preview.redd.it/abc.jpg", "width": 1200, "height": 400]]]]
    #expect(try resize(known) == ImageProcessors.Resize(width: 400, unit: .points, upscale: true).identifier)
    // Shown in a square until it loads: a width-only resize would leave it too short to fill one.
    let square = ImageProcessors.Resize(size: CGSize(width: 400, height: 400), unit: .points, contentMode: .aspectFill, crop: false, upscale: true)
    #expect(try resize(nil) == square.identifier)
  }

  /// Runs a request's decoding and processors on a large JPEG, as the pipeline does, at the
  /// screen's scale: the image comes out the column's width in points, with the pixels a sharp
  /// one needs, however wide it is.
  @Test(arguments: [(4000, 1000), (1200, 1200), (900, 2700)])
  func decodesASingleImageSharpAtTheWidthItsShown(width: Int, height: Int) throws {
    // In the app the window's scale comes from its screen, which is also what the renderers and
    // Nuke use; a test host has no window to report it.
    WindowMetrics.shared.update(displayScale: UIGraphicsImageRendererFormat.preferred().scale)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let jpeg = try #require(UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
      UIColor.systemTeal.setFill()
      context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
    }.jpegData(compressionQuality: 0.8))
    let preview = ["images": [["source": ["url": "https://preview.redd.it/abc.jpg", "width": width, "height": height]]]]
    guard case let .imgs(images)? = try extract(["url": "https://i.redd.it/abc.jpg", "domain": "i.redd.it", "preview": preview]),
          let request = images.first?.request
    else { Issue.record("expected an image")
      return
    }
    let thumbnail = try #require(request.userInfo[.thumbnailKey] as? ImageRequest.ThumbnailOptions)
    var image = try #require(thumbnail.makeThumbnail(with: jpeg))
    for processor in request.processors {
      image = try #require(processor.process(image))
    }
    let scale = CGFloat.screenScale
    #expect(image.scale == scale, "scale \(image.scale), screen \(scale), \(image.size) points")
    #expect(abs(image.size.width - 400) <= 1)
    #expect(try abs(CGFloat(#require(image.cgImage).width) - 400 * scale) <= scale)
    #expect(abs(image.size.height - 400 * CGFloat(height) / CGFloat(width)) <= 1)
  }

  @Test func playsTheFallbackMP4WhenHLSIsMissing() throws {
    let result = try extract([
      "media": ["reddit_video": ["fallback_url": "https://v.redd.it/abc/DASH_720.mp4", "width": 1280, "height": 720]],
    ])
    guard case let .video(video) = result else { Issue.record("expected video, got \(String(describing: result))")
      return
    }
    #expect(video.url.absoluteString == "https://v.redd.it/abc/DASH_720.mp4")
    #expect(video.size == CGSize(width: 1280, height: 720))
  }

  @Test func usesThePreviewSizeWhenVideoSizeIsMissing() throws {
    let result = try extract([
      "preview": [
        "reddit_video_preview": ["hls_url": "https://v.redd.it/abc/HLSPlaylist.m3u8"],
        "images": [["source": ["url": "https://preview.redd.it/abc.jpg?s=sig", "width": 300, "height": 200]]],
      ],
    ])
    guard case let .video(video) = result else { Issue.record("expected video, got \(String(describing: result))")
      return
    }
    #expect(video.size == CGSize(width: 300, height: 200))
  }

  @Test func acceptsYouTubeEmbedsWithOnlyAVideoID() throws {
    let result = try extract([
      "media": ["type": "youtube.com", "oembed": ["html": "<iframe src=\"https://www.youtube.com/embed/dQw4w9WgXcQ?feature=oembed\"></iframe>"]],
    ])
    guard case let .yt(yt) = result else { Issue.record("expected youtube, got \(String(describing: result))")
      return
    }
    #expect(yt.videoID == "dQw4w9WgXcQ")
    #expect(yt.thumbnailURL.absoluteString == "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")
  }

  @Test func readsTheYouTubeIDFromAnEmbedURLWithoutAQuery() throws {
    let result = try extract([
      "media": ["type": "youtube.com", "oembed": ["html": "<iframe width=\"356\" src=\"https://www.youtube.com/embed/dQw4w9WgXcQ\" frameborder=\"0\"></iframe>"]],
    ])
    guard case let .yt(yt) = result else { Issue.record("expected youtube, got \(String(describing: result))")
      return
    }
    #expect(yt.videoID == "dQw4w9WgXcQ")
  }

  @Test func keepsTheSignatureOnPreviewImageURLs() throws {
    let result = try extract(["url": "https://preview.redd.it/abc.jpg?width=640&s=signature"])
    guard case let .imgs(imgs) = result else { Issue.record("expected image, got \(String(describing: result))")
      return
    }
    #expect(imgs.first?.url.absoluteString == "https://preview.redd.it/abc.jpg?width=640&s=signature")
  }

  @Test func dropsTrackingQueriesFromOtherImageURLs() throws {
    let result = try extract(["url": "https://i.imgur.com/abc.png?utm_source=reddit"])
    guard case let .imgs(imgs) = result else { Issue.record("expected image, got \(String(describing: result))")
      return
    }
    #expect(imgs.first?.url.absoluteString == "https://i.imgur.com/abc.png")
  }

  @Test func keepsOtherQueriesOnImageURLs() throws {
    let result = try extract(["url": "https://cdn.example.com/photo.png?token=abc&utm_source=reddit"])
    guard case let .imgs(imgs) = result else { Issue.record("expected image, got \(String(describing: result))")
      return
    }
    #expect(imgs.first?.url.absoluteString == "https://cdn.example.com/photo.png?token=abc")
  }

  @Test func fallsThroughWhenNoGalleryItemIsUsable() throws {
    let result = try extract([
      "is_gallery": true,
      "gallery_data": ["items": [["media_id": "missing", "id": 1]]],
      "media_metadata": [:],
      "preview": ["images": [["source": ["url": "https://preview.redd.it/abc.jpg?s=sig", "width": 300, "height": 200]]]],
    ])
    guard case let .imgs(imgs) = result else { Issue.record("expected preview image, got \(String(describing: result))")
      return
    }
    #expect(imgs.first?.url.absoluteString == "https://i.redd.it/abc.jpg")
  }

  @Test func givesVideosAndGIFsThePreviewAsPoster() throws {
    let preview: [String: Any] = ["images": [["source": ["url": "https://preview.redd.it/abc.jpg?width=640&amp;s=sig", "width": 640, "height": 480]]]]

    let video = try extract([
      "media": ["reddit_video": ["hls_url": "https://v.redd.it/abc/HLSPlaylist.m3u8", "width": 640, "height": 480]],
      "preview": preview,
    ])
    guard case let .video(shared) = video else { Issue.record("expected video, got \(String(describing: video))")
      return
    }
    #expect(shared.posterURL?.host == "preview.redd.it")
    #expect(shared.posterURL?.query?.contains("s=sig") == true)

    let gif = try extract(["url": "https://i.redd.it/abc.gif", "preview": preview])
    guard case let .imgs(imgs) = gif else { Issue.record("expected image, got \(String(describing: gif))")
      return
    }
    #expect(imgs.first?.posterURL?.host == "preview.redd.it")

    let still = try extract(["url": "https://i.redd.it/abc.png", "preview": preview])
    guard case let .imgs(stills) = still else { Issue.record("expected image, got \(String(describing: still))")
      return
    }
    #expect(stills.first?.posterURL == nil)
  }

  @Test func recognizesGIFsByPathExtension() throws {
    #expect(try #require(URL(string: "https://i.redd.it/abc.gif")?.isGIF))
    #expect(try #require(URL(string: "https://i.redd.it/abc.GIF")?.isGIF))
    #expect(try #require(URL(string: "https://i.redd.it/abc.gif?s=signature")?.isGIF))
    #expect(try !#require(URL(string: "https://i.redd.it/abc.png?x=.gif")?.isGIF))
  }

  @Test func aLinkCardOpensFromTheFeedWhateverTheMediaSetting() throws {
    let link = try #require(try extract([:]))
    let video = try #require(try extract(["media": ["reddit_video": ["fallback_url": "https://v.redd.it/abc/DASH_720.mp4", "width": 1280, "height": 720]]]))
    guard case .link = link else {
      Issue.record("expected a link, got \(link)")
      return
    }
    #expect(link.isTappableInFeed(mediaTappable: false))
    #expect(!video.isTappableInFeed(mediaTappable: false))
    #expect(video.isTappableInFeed(mediaTappable: true))
  }
}

/// A canvas feed shows no link previews, so its posts' previews download the linked page only
/// once they show.
struct DeferredLinkPreviewTests {
  private func postData(_ overrides: [String: Any]) throws -> PostData {
    var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(postSampleData)) as? [String: Any])
    json["is_self"] = false
    json.merge(overrides) { $1 }
    return try JSONDecoder().decode(PostData.self, from: JSONSerialization.data(withJSONObject: json))
  }

  @Test func aDeferredPreviewLoadsWhenItShows() throws {
    let data = try postData(["url": "https://example.com/deferred-\(UUID().uuidString)", "domain": "example.com"])
    guard case let .link(model) = mediaExtractor(compact: false, contentWidth: 400, data, fetchLinkMetadata: false) else {
      Issue.record("expected a link")
      return
    }
    #expect(!model.hasStartedLoading)
    model.loadIfNeeded()
    #expect(model.hasStartedLoading)
  }

  @Test func aLayoutThatShowsPreviewsStartsADeferredOne() throws {
    let url = try #require(URL(string: "https://example.com/shared-\(UUID().uuidString)"))
    let deferred = PreviewModel.shared(url, compact: true, fetch: false)
    #expect(!deferred.hasStartedLoading)
    #expect(PreviewModel.shared(url, compact: true) === deferred)
    #expect(deferred.hasStartedLoading)
  }

  @Test func aCrosspostDefersItsOriginalsPreviewToo() throws {
    var original = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(postSampleData)) as? [String: Any])
    original["is_self"] = false
    original["url"] = "https://example.com/original-\(UUID().uuidString)"
    original["domain"] = "example.com"
    let data = try postData(["url": "https://example.com/outer", "crosspost_parent_list": [original]])
    guard case let .repost(embedded) = mediaExtractor(compact: false, contentWidth: 400, data, fetchLinkMetadata: false),
          case let .link(model) = embedded.helioData?.extractedMedia
    else {
      Issue.record("expected a crosspost of a link")
      return
    }
    #expect(!model.hasStartedLoading)
  }

  /// Canvas shows no video, so a Streamable link waits until its media shows, and resolves once.
  @Test func aDeferredStreamableResolvesOnlyWhenItShows() throws {
    let data = try postData(["url": "https://streamable.com/deferred\(UUID().uuidString.prefix(8))", "domain": "streamable.com"])
    let post = Post(data: data, contentWidth: 400, theme: defaultTheme, fetchAvatar: false, fetchLinkMetadata: false)
    let helioData = try #require(post.helioData)
    guard case .streamable = helioData.extractedMedia else {
      Issue.record("expected a Streamable link")
      return
    }
    #expect(helioData.deferredMedia != nil)

    // Stands in for the request, which the test doesn't make.
    var resolved = 0
    helioData.deferredMedia = { resolved += 1 }
    helioData.resolveDeferredMedia()
    helioData.resolveDeferredMedia()
    #expect(resolved == 1)
  }

  /// Canvas shows no linked user, post, comment or subreddit, so each loads only once its media
  /// shows, as on the post page; large and compact feeds load them as they're laid out.
  @Test(arguments: [
    "https://www.reddit.com/u/placeholder_user",
    "https://www.reddit.com/r/apple/comments/abc123/a_title/",
    "https://www.reddit.com/r/apple/comments/abc123/a_title/def456/",
    "https://www.reddit.com/r/apple/",
  ])
  func aLinkedRedditEntityLoadsOnlyWhenItShows(url: String) throws {
    let data = try postData(["url": url, "domain": "reddit.com"])
    let eager = Post(data: data, contentWidth: 400, theme: defaultTheme, fetchAvatar: false, fetchLinkMetadata: true)
    #expect(eager.helioData?.deferredMedia == nil)

    let post = Post(data: data, contentWidth: 400, theme: defaultTheme, fetchAvatar: false, fetchLinkMetadata: false)
    let helioData = try #require(post.helioData)
    switch helioData.extractedMediaForcedNormal {
    case .post, .comment, .user, .subreddit: break
    default: Issue.record("expected a linked Reddit entity")
    }
    #expect(helioData.deferredMedia != nil)

    // Stands in for the request, which the test doesn't make.
    var resolved = 0
    helioData.deferredMedia = { resolved += 1 }
    helioData.resolveDeferredMedia()
    helioData.resolveDeferredMedia()
    #expect(resolved == 1)

    // Refreshing the post once its media has shown, as its page does, loads it right away.
    post.setupHelioData(theme: defaultTheme, fetchAvatar: false)
    #expect(helioData.fetchesLinkMetadata)
    #expect(helioData.deferredMedia == nil)
  }
}
