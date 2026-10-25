import Foundation
import Testing
@testable import winston

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
    mediaExtractor(compact: false, contentWidth: 400, try postData(overrides))
  }

  @Test func showsCrosspostsAsTheOriginalPostEvenWithVideoMedia() throws {
    let original = try JSONSerialization.jsonObject(with: JSONEncoder().encode(postSampleData))
    let result = try extract([
      "url": "https://v.redd.it/abc123",
      "preview": ["reddit_video_preview": ["hls_url": "https://v.redd.it/abc123/HLSPlaylist.m3u8", "width": 640, "height": 360]],
      "crosspost_parent_list": [original],
    ])
    guard case .repost = result else { Issue.record("expected repost, got \(String(describing: result))"); return }
  }

  @Test func playsTheFallbackMP4WhenHLSIsMissing() throws {
    let result = try extract([
      "media": ["reddit_video": ["fallback_url": "https://v.redd.it/abc/DASH_720.mp4", "width": 1280, "height": 720]],
    ])
    guard case .video(let video) = result else { Issue.record("expected video, got \(String(describing: result))"); return }
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
    guard case .video(let video) = result else { Issue.record("expected video, got \(String(describing: result))"); return }
    #expect(video.size == CGSize(width: 300, height: 200))
  }

  @Test func acceptsYouTubeEmbedsWithOnlyAVideoID() throws {
    let result = try extract([
      "media": ["type": "youtube.com", "oembed": ["html": "<iframe src=\"https://www.youtube.com/embed/dQw4w9WgXcQ?feature=oembed\"></iframe>"]],
    ])
    guard case .yt(let yt) = result else { Issue.record("expected youtube, got \(String(describing: result))"); return }
    #expect(yt.videoID == "dQw4w9WgXcQ")
    #expect(yt.thumbnailURL.absoluteString == "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")
  }

  @Test func keepsTheSignatureOnPreviewImageURLs() throws {
    let result = try extract(["url": "https://preview.redd.it/abc.jpg?width=640&s=signature"])
    guard case .imgs(let imgs) = result else { Issue.record("expected image, got \(String(describing: result))"); return }
    #expect(imgs.first?.url.absoluteString == "https://preview.redd.it/abc.jpg?width=640&s=signature")
  }

  @Test func dropsTrackingQueriesFromOtherImageURLs() throws {
    let result = try extract(["url": "https://i.imgur.com/abc.png?utm_source=reddit"])
    guard case .imgs(let imgs) = result else { Issue.record("expected image, got \(String(describing: result))"); return }
    #expect(imgs.first?.url.absoluteString == "https://i.imgur.com/abc.png")
  }

  @Test func fallsThroughWhenNoGalleryItemIsUsable() throws {
    let result = try extract([
      "is_gallery": true,
      "gallery_data": ["items": [["media_id": "missing", "id": 1]]],
      "media_metadata": [:],
      "preview": ["images": [["source": ["url": "https://preview.redd.it/abc.jpg?s=sig", "width": 300, "height": 200]]]],
    ])
    guard case .imgs(let imgs) = result else { Issue.record("expected preview image, got \(String(describing: result))"); return }
    #expect(imgs.first?.url.absoluteString == "https://i.redd.it/abc.jpg")
  }

  @Test func givesVideosAndGIFsThePreviewAsPoster() throws {
    let preview: [String: Any] = ["images": [["source": ["url": "https://preview.redd.it/abc.jpg?width=640&amp;s=sig", "width": 640, "height": 480]]]]

    let video = try extract([
      "media": ["reddit_video": ["hls_url": "https://v.redd.it/abc/HLSPlaylist.m3u8", "width": 640, "height": 480]],
      "preview": preview,
    ])
    guard case .video(let shared) = video else { Issue.record("expected video, got \(String(describing: video))"); return }
    #expect(shared.posterURL?.host == "preview.redd.it")
    #expect(shared.posterURL?.query?.contains("s=sig") == true)

    let gif = try extract(["url": "https://i.redd.it/abc.gif", "preview": preview])
    guard case .imgs(let imgs) = gif else { Issue.record("expected image, got \(String(describing: gif))"); return }
    #expect(imgs.first?.posterURL?.host == "preview.redd.it")

    let still = try extract(["url": "https://i.redd.it/abc.png", "preview": preview])
    guard case .imgs(let stills) = still else { Issue.record("expected image, got \(String(describing: still))"); return }
    #expect(stills.first?.posterURL == nil)
  }
}
