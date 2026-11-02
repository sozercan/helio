import Foundation
import Testing
@testable import HelioKit

struct PostLayoutTests {
  @Test func canvasWinsOverCompact() {
    #expect(PostLayout.of("pics", compactPerSubreddit: ["pics": true], compactByDefault: false, canvasSubreddits: ["pics"]) == .canvas)
    #expect(PostLayout.of("pics", compactPerSubreddit: ["pics": true], compactByDefault: false, canvasSubreddits: []) == .compact)
    #expect(PostLayout.of("pics", compactPerSubreddit: [:], compactByDefault: true, canvasSubreddits: []) == .compact)
    #expect(PostLayout.of("pics", compactPerSubreddit: ["pics": false], compactByDefault: true, canvasSubreddits: []) == .large)
  }

  @Test func applyingALayoutSetsOnlyThatSubreddit() {
    var compact = ["apple": true]
    var canvas: Set<String> = []
    PostLayout.canvas.apply(to: "pics", compactPerSubreddit: &compact, canvasSubreddits: &canvas)
    #expect(canvas == ["pics"])
    #expect(compact == ["apple": true])
    #expect(PostLayout.of("pics", compactPerSubreddit: compact, compactByDefault: false, canvasSubreddits: canvas) == .canvas)

    PostLayout.compact.apply(to: "pics", compactPerSubreddit: &compact, canvasSubreddits: &canvas)
    #expect(canvas.isEmpty)
    #expect(compact == ["apple": true, "pics": true])

    PostLayout.large.apply(to: "pics", compactPerSubreddit: &compact, canvasSubreddits: &canvas)
    #expect(PostLayout.of("pics", compactPerSubreddit: compact, compactByDefault: true, canvasSubreddits: canvas) == .large)
  }

  /// Saved has comments, which the canvas has no tiles for.
  @Test func savedOffersNoCanvas() {
    #expect(PostLayout.available(for: "pics") == PostLayout.allCases)
    #expect(!PostLayout.available(for: savedKeyword).contains(.canvas))
    // A canvas stored for it from before shows rows.
    #expect(!PostLayout.isCanvas(savedKeyword, canvasSubreddits: [savedKeyword]))
    #expect(PostLayout.of(savedKeyword, compactPerSubreddit: [:], compactByDefault: true, canvasSubreddits: [savedKeyword]) == .compact)
  }
}

@MainActor
struct CanvasTileTests {
  /// A refresh brings new models for the same posts; their tiles have to draw the new ones.
  @Test func aRefreshedPostRedrawsItsTile() {
    let sub = Subreddit(id: "pics")
    let post = Post(id: "abc")
    let theme = defaultTheme.postLinks.theme
    #expect(CanvasTile(post: post, sub: sub, size: 100, theme: theme) == CanvasTile(post: post, sub: sub, size: 100, theme: theme))
    #expect(CanvasTile(post: post, sub: sub, size: 100, theme: theme) != CanvasTile(post: Post(id: "abc"), sub: sub, size: 100, theme: theme))
  }
}

struct CanvasGridTests {
  @Test(arguments: [(CGFloat(402), 2), (375, 2), (480, 3), (700, 4), (300, 2), (1000, 6)])
  func columnsFitTheWidth(width: CGFloat, columns: Int) {
    let grid = CanvasGrid(width: width)
    #expect(grid.columns == columns)
    #expect(grid.hinge == nil)
    #expect(grid.tileSize >= min(CanvasGrid.minTileWidth, (width - CanvasGrid.spacing) / 2) - 1)
    // The tiles and the gaps between them fit the width.
    #expect(grid.tileSize * CGFloat(grid.columns) + CanvasGrid.spacing * CGFloat(grid.columns - 1) <= width)
  }

  @Test func aHingeAcrossTheGridSplitsItEvenly() throws {
    // An open iPhone Duo spanned: two 420-point screens and a 28-point hinge.
    let grid = CanvasGrid(width: 868, division: 420 ... 448)
    #expect(grid.columns % 2 == 0)
    let hinge = try #require(grid.hinge)
    #expect(hinge.columnsBefore * 2 == grid.columns)
    #expect(hinge.leadingWidth == 420)
    #expect(hinge.width == 28)
    // Each side's tiles fit before and after the hinge.
    let side = grid.tileSize * CGFloat(hinge.columnsBefore) + CanvasGrid.spacing * CGFloat(hinge.columnsBefore - 1)
    #expect(side <= 420)
  }

  @Test func aHingeOutsideTheGridIsIgnored() {
    // The posts tab's feed column ends at the hinge.
    let grid = CanvasGrid(width: 420, division: 420 ... 448)
    #expect(grid.hinge == nil)
    #expect(grid.columns == 2)
  }

  @Test func rowsKeepTheFeedsOrder() {
    let grid = CanvasGrid(width: 480)
    let rows = grid.rows(Array(1 ... 7))
    #expect(rows.map(Array.init) == [[1, 2, 3], [4, 5, 6], [7]])
    #expect(grid.rows([Int]()).isEmpty)
  }
}

struct CanvasThumbnailTests {
  private func data(_ edit: (inout [String: Any]) -> Void) throws -> PostData {
    var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(postSampleData)) as? [String: Any])
    json["is_self"] = false
    edit(&json)
    return try JSONDecoder().decode(PostData.self, from: JSONSerialization.data(withJSONObject: json))
  }

  @Test func picksTheSmallestRenditionThatCoversTheTile() throws {
    let data = try data { json in
      json["preview"] = ["images": [[
        "source": ["url": "https://preview.redd.it/a.jpg?width=2000&amp;s=src", "width": 2000, "height": 1500],
        "resolutions": [
          ["url": "https://preview.redd.it/a.jpg?width=320&amp;s=x", "width": 320, "height": 240],
          ["url": "https://preview.redd.it/a.jpg?width=640&amp;s=y", "width": 640, "height": 480],
          ["url": "https://preview.redd.it/a.jpg?width=1080&amp;s=w", "width": 1080, "height": 810],
          ["url": "https://preview.redd.it/a.jpg?width=108&amp;s=z", "width": 108, "height": 81],
        ],
      ]]]
    }
    // The tile is a square from the middle, so the shorter side has to cover it: 640×480 is
    // too short for 600.
    #expect(CanvasThumbnail.url(for: data, pixelWidth: 600)?.absoluteString == "https://preview.redd.it/a.jpg?width=1080&s=w")
    #expect(CanvasThumbnail.url(for: data, pixelWidth: 300)?.absoluteString == "https://preview.redd.it/a.jpg?width=640&s=y")
    #expect(CanvasThumbnail.url(for: data, pixelWidth: 240)?.absoluteString == "https://preview.redd.it/a.jpg?width=320&s=x")
    // Larger than every rendition: the source.
    #expect(CanvasThumbnail.url(for: data, pixelWidth: 3000)?.absoluteString == "https://preview.redd.it/a.jpg?width=2000&s=src")
    #expect(CanvasThumbnail.kind(of: data) == .image)
  }

  @Test func galleriesShowTheirFirstImage() throws {
    let data = try data { json in
      json["is_gallery"] = true
      json["gallery_data"] = ["items": [["media_id": "second", "id": 2], ["media_id": "first", "id": 1]]]
      json["media_metadata"] = [
        "first": ["status": "valid", "s": ["x": 1200, "y": 900, "u": "https://i.redd.it/first.jpg"]],
        "second": ["status": "valid", "p": [["x": 640, "y": 480, "u": "https://preview.redd.it/second-640.jpg"]], "s": ["x": 1200, "y": 900, "u": "https://i.redd.it/second.jpg"]],
      ]
    }
    #expect(CanvasThumbnail.url(for: data, pixelWidth: 400)?.absoluteString == "https://preview.redd.it/second-640.jpg")
    #expect(CanvasThumbnail.url(for: data, pixelWidth: 600)?.absoluteString == "https://i.redd.it/second.jpg")
    #expect(CanvasThumbnail.kind(of: data) == .gallery(2))
  }

  @Test func anImageLinkWithoutAPreviewShowsTheImage() throws {
    let data = try data { json in
      json["preview"] = nil
      json["post_hint"] = "image"
      json["url"] = "https://i.redd.it/abc.jpg"
    }
    #expect(CanvasThumbnail.url(for: data, pixelWidth: 300)?.absoluteString == "https://i.redd.it/abc.jpg")
    #expect(CanvasThumbnail.kind(of: data) == .image)
  }

  @Test func textPostsAndBareLinksHaveNoPicture() throws {
    let text = try data { $0["is_self"] = true }
    #expect(CanvasThumbnail.url(for: text, pixelWidth: 300) == nil)
    let link = try data { json in
      json["preview"] = nil
      json["post_hint"] = "link"
      json["url"] = "https://example.com/article"
    }
    #expect(CanvasThumbnail.url(for: link, pixelWidth: 300) == nil)
  }

  /// A crosspost shows the original's picture, so either post's flags hide it.
  @Test func aCrosspostIsHiddenWhenEitherPostIsNSFWOrASpoiler() throws {
    let plain = try data { _ in }
    #expect(CanvasThumbnail.veil(for: plain) == nil)
    #expect(try CanvasThumbnail.veil(for: data { $0["over_18"] = true }) == .nsfw)
    #expect(try CanvasThumbnail.veil(for: data { $0["spoiler"] = true }) == .spoiler)

    let original = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(postSampleData)) as? [String: Any])
    func crosspost(_ flag: String, onOriginal: Bool) throws -> PostData {
      var parent = original
      if onOriginal {
        parent[flag] = true
      }
      return try data { json in
        json["crosspost_parent_list"] = [parent]
        if !onOriginal {
          json[flag] = true
        }
      }
    }
    #expect(try CanvasThumbnail.veil(for: crosspost("over_18", onOriginal: true)) == .nsfw)
    #expect(try CanvasThumbnail.veil(for: crosspost("spoiler", onOriginal: true)) == .spoiler)
    #expect(try CanvasThumbnail.veil(for: crosspost("over_18", onOriginal: false)) == .nsfw)
    #expect(try CanvasThumbnail.veil(for: data { $0["crosspost_parent_list"] = [original] }) == nil)
    // NSFW wins over a spoiler on the other post.
    var nsfwOriginal = original
    nsfwOriginal["over_18"] = true
    let spoilerOfNSFW = try data { json in
      json["spoiler"] = true
      json["crosspost_parent_list"] = [nsfwOriginal]
    }
    #expect(CanvasThumbnail.veil(for: spoilerOfNSFW) == .nsfw)
  }
}
