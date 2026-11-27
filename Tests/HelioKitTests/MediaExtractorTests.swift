import Foundation
import Nuke
import Testing
import UIKit
@testable import HelioKit

struct MediaExtractorTests {
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
    let square = ImageProcessors.Resize(size: CGSize(width: 400, height: 400), unit: .points, contentMode: .aspectFill, crop: false, upscale: true)
    #expect(try resize(nil) == square.identifier)
  }

  @Test(arguments: [(4000, 1000), (1200, 1200), (900, 2700)])
  func decodesASingleImageSharpAtTheWidthItsShown(width: Int, height: Int) throws {
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

  @Test func repairsFailedGalleryMetadataUsingThumbnailExtensionAndJpegFallback() throws {
    let result = try extract([
      "is_gallery": true,
      "thumbnail": "https://preview.redd.it/abc123.png?width=140&amp;s=sig",
      "gallery_data": ["items": [
        ["media_id": "abc123", "id": 1],
        ["media_id": "def456", "id": 2],
      ]],
      "media_metadata": [
        "abc123": ["status": "failed"],
        "def456": ["status": "failed"],
      ],
    ])
    guard case let .imgs(imgs) = result else {
      Issue.record("expected repaired gallery images, got \(String(describing: result))")
      return
    }
    #expect(imgs.map(\.url.absoluteString) == [
      "https://i.redd.it/abc123.png",
      "https://i.redd.it/def456.png",
    ])
    #expect(imgs.allSatisfy { $0.size == .zero })
  }

  @Test func repairsFailedGalleryMetadataWithoutThumbnailUsingJpeg() throws {
    let result = try extract([
      "is_gallery": true,
      "thumbnail": "default",
      "gallery_data": ["items": [["media_id": "abc123", "id": 1]]],
      "media_metadata": ["abc123": ["status": "failed"]],
    ])
    guard case let .imgs(imgs) = result else {
      Issue.record("expected repaired gallery image, got \(String(describing: result))")
      return
    }
    #expect(imgs.map(\.url.absoluteString) == ["https://i.redd.it/abc123.jpeg"])
  }

  @Test func doesNotRepairFailedGalleryMetadataWithUnsafeMediaID() throws {
    let result = try extract([
      "is_gallery": true,
      "gallery_data": ["items": [["media_id": "../evil", "id": 1]]],
      "media_metadata": ["../evil": ["status": "failed"]],
    ])
    guard case .link = result else {
      Issue.record("expected fallthrough to link for unsafe media_id, got \(String(describing: result))")
      return
    }
  }

  @Test func repairsIncompleteRedditHostedGIFMetadata() throws {
    let result = try extract([
      "is_gallery": true,
      "gallery_data": ["items": [["media_id": "gif123", "id": 1]]],
      "media_metadata": [
        "gif123": [
          "status": "unprocessed",
          "e": "AnimatedImage",
          "s": ["x": 480, "y": 270, "gif": "https://i.redd.it/gif123.gif"],
        ],
      ],
    ])
    guard case let .imgs(imgs) = result else {
      Issue.record("expected repaired gif, got \(String(describing: result))")
      return
    }
    #expect(imgs.map(\.url.absoluteString) == ["https://i.redd.it/gif123.gif"])
    #expect(imgs.first?.size == CGSize(width: 480, height: 270))
  }

  @Test func detectsRedditHostedGIFSourceWithQueryStringAndPreservesMimeOnFailedItem() throws {
    let gifWithQuery = try extract([
      "is_gallery": true,
      "gallery_data": ["items": [["media_id": "gifq1", "id": 1]]],
      "media_metadata": [
        "gifq1": [
          "status": "unprocessed",
          "s": ["x": 320, "y": 240, "gif": "https://i.redd.it/gifq1.gif?s=signature"],
        ],
      ],
    ])
    guard case let .imgs(gifImgs) = gifWithQuery else {
      Issue.record("expected gif with query string, got \(String(describing: gifWithQuery))")
      return
    }
    #expect(gifImgs.map(\.url.absoluteString) == ["https://i.redd.it/gifq1.gif"])

    let failedWithMime = try extract([
      "is_gallery": true,
      "thumbnail": "default",
      "gallery_data": ["items": [["media_id": "png123", "id": 1]]],
      "media_metadata": [
        "png123": [
          "status": "failed",
          "m": "image/png",
        ],
      ],
    ])
    guard case let .imgs(pngImgs) = failedWithMime else {
      Issue.record("expected failed item to keep mime png, got \(String(describing: failedWithMime))")
      return
    }
    #expect(pngImgs.map(\.url.absoluteString) == ["https://i.redd.it/png123.png"])

    let previewMp4Gif = try extract([
      "is_gallery": true,
      "gallery_data": ["items": [["media_id": "gifmp4", "id": 1]]],
      "media_metadata": [
        "gifmp4": [
          "status": "unprocessed",
          "s": ["x": 400, "y": 300, "mp4": "https://preview.redd.it/gifmp4.gif?width=400&amp;format=mp4&amp;s=sig"],
        ],
      ],
    ])
    guard case let .imgs(mp4Imgs) = previewMp4Gif else {
      Issue.record("expected preview.redd.it format=mp4 to recover as gif, got \(String(describing: previewMp4Gif))")
      return
    }
    #expect(mp4Imgs.map(\.url.absoluteString) == ["https://i.redd.it/gifmp4.gif"])

    let nonFormatMp4 = try extract([
      "is_gallery": true,
      "gallery_data": ["items": [["media_id": "notgif", "id": 1]]],
      "media_metadata": [
        "notgif": [
          "status": "unprocessed",
          "s": ["x": 400, "y": 300, "u": "https://preview.redd.it/notgif.jpg?note=format=mp4&amp;s=sig"],
        ],
      ],
    ])
    guard case .link = nonFormatMp4 else {
      Issue.record("expected unrelated mp4 query param not to match gif, got \(String(describing: nonFormatMp4))")
      return
    }
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
    for compact in [false, true] {
      #expect(link.isTappableInFeed(mediaTappable: false, compact: compact))
      #expect(!video.isTappableInFeed(mediaTappable: false, compact: compact))
      #expect(video.isTappableInFeed(mediaTappable: true, compact: compact))
    }
  }
}

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

  @Test func aDeferredStreamableResolvesOnlyWhenItShows() throws {
    let data = try postData(["url": "https://streamable.com/deferred\(UUID().uuidString.prefix(8))", "domain": "streamable.com"])
    let post = Post(data: data, contentWidth: 400, theme: defaultTheme, fetchAvatar: false, fetchLinkMetadata: false)
    let helioData = try #require(post.helioData)
    guard case .streamable = helioData.extractedMedia else {
      Issue.record("expected a Streamable link")
      return
    }
    #expect(helioData.deferredMedia != nil)

    var resolved = 0
    helioData.deferredMedia = { resolved += 1 }
    helioData.resolveDeferredMedia()
    helioData.resolveDeferredMedia()
    #expect(resolved == 1)
  }

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

    var resolved = 0
    helioData.deferredMedia = { resolved += 1 }
    helioData.resolveDeferredMedia()
    helioData.resolveDeferredMedia()
    #expect(resolved == 1)

    post.setupHelioData(theme: defaultTheme, fetchAvatar: false)
    #expect(helioData.fetchesLinkMetadata)
    #expect(helioData.deferredMedia == nil)
  }
}

struct FeedLinkTapTests {
  @Test func linkedRedditCardsOpenFromTheFeedWhilePicturesFollowTheSetting() {
    for compact in [false, true] {
      #expect(MediaExtractedType.post(nil).isTappableInFeed(mediaTappable: false, compact: compact))
      #expect(MediaExtractedType.subreddit(nil).isTappableInFeed(mediaTappable: false, compact: compact))
      #expect(MediaExtractedType.user(nil).isTappableInFeed(mediaTappable: false, compact: compact))
      #expect(!MediaExtractedType.imgs([]).isTappableInFeed(mediaTappable: false, compact: compact))
    }
    #expect(!MediaExtractedType.comment(nil).isTappableInFeed(mediaTappable: false, compact: false))
    #expect(MediaExtractedType.comment(nil).isTappableInFeed(mediaTappable: false, compact: true))
  }
}
