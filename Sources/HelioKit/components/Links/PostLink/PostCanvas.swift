//
//  PostCanvas.swift
//  Helio
//
//  The canvas post layout (`PostLayout.canvas`), after Alien Blue's: a grid of large
//  thumbnails. Posts without a picture (text posts, links without a preview) are tiles with
//  their title, so the grid keeps the feed's order and every post stays a tap away.
//

import Nuke
import SwiftUI

/// How the canvas fits its square tiles into a feed `width` wide.
struct CanvasGrid: Equatable {
  /// The narrowest a tile gets: two tiles across an iPhone, three to four in a wider column.
  static let minTileWidth: CGFloat = 150
  /// Between tiles, across and down.
  static let spacing: CGFloat = 2

  /// A vertical hinge across the grid (an open iPhone Duo): tiles go on either side of it.
  struct Hinge: Equatable {
    /// The columns before it, as many as after it.
    let columnsBefore: Int
    /// The width the grid has before it.
    let leadingWidth: CGFloat
    /// Its own width, which no tile spans.
    let width: CGFloat
  }

  let columns: Int
  let tileSize: CGFloat
  let hinge: Hinge?

  /// `division` is the hinge's horizontal span in the grid's coordinates, if the window has one.
  init(width: CGFloat, division: ClosedRange<CGFloat>? = nil) {
    let spacing = Self.spacing
    func fitting(_ width: CGFloat) -> Int {
      max(1, Int(((width + spacing) / (Self.minTileWidth + spacing)).rounded(.down)))
    }
    func tile(_ width: CGFloat, _ columns: Int) -> CGFloat {
      max(0, ((width - spacing * CGFloat(columns - 1)) / CGFloat(columns)).rounded(.down))
    }
    if let division, division.lowerBound > 0, division.upperBound < width {
      // An even number of columns, half on each side, so no tile is cut by the hinge.
      let leading = division.lowerBound
      let trailing = width - division.upperBound
      let perSide = min(fitting(leading), fitting(trailing))
      columns = perSide * 2
      tileSize = min(tile(leading, perSide), tile(trailing, perSide))
      hinge = Hinge(columnsBefore: perSide, leadingWidth: leading, width: division.upperBound - division.lowerBound)
    } else {
      columns = max(2, fitting(width))
      tileSize = tile(width, columns)
      hinge = nil
    }
  }

  /// `items` in rows of `columns`.
  func rows<T>(_ items: [T]) -> [ArraySlice<T>] {
    stride(from: 0, to: items.count, by: columns).map { items[$0 ..< min($0 + columns, items.count)] }
  }
}

/// The picture a post shows in the canvas.
enum CanvasThumbnail {
  /// What the post is, for the glyph on its tile.
  enum Kind: Equatable {
    case image, gallery(Int), video, link
  }

  /// The smallest of Reddit's renditions at least `pixelWidth` wide, else the largest. Nil for
  /// posts without a picture: text posts, and links without a preview.
  static func url(for data: PostData, pixelWidth: CGFloat) -> URL? {
    // A crosspost shows the original's picture.
    let data = data.crosspost_parent_list?.first ?? data
    guard !data.is_self else { return nil }
    if data.is_gallery == true, let first = data.gallery_data?.items?.first, case let item?? = data.media_metadata?[first.media_id] {
      let sizes = (item.p ?? []) + [item.s].compactMap(\.self)
      if let url = smallest(sizes.map { ($0.x, $0.u) }, atLeast: pixelWidth) {
        return url
      }
    }
    if let image = data.preview?.images?.first {
      let sizes = (image.resolutions ?? []) + [image.source].compactMap(\.self)
      if let url = smallest(sizes.map { ($0.width ?? 0, $0.url) }, atLeast: pixelWidth) {
        return url
      }
    }
    if let thumbnail = data.media?.oembed?.thumbnail_url {
      return URL(string: thumbnail.escape)
    }
    return nil
  }

  static func smallest(_ sizes: [(width: Int, url: String?)], atLeast pixelWidth: CGFloat) -> URL? {
    let usable = sizes.compactMap { size in size.url.flatMap { URL(string: $0.escape) }.map { (size.width, $0) } }
      .sorted { $0.0 < $1.0 }
    return (usable.first { CGFloat($0.0) >= pixelWidth } ?? usable.last)?.1
  }

  static func kind(of data: PostData) -> Kind {
    let data = data.crosspost_parent_list?.first ?? data
    if data.is_gallery == true {
      return .gallery(data.gallery_data?.items?.count ?? 0)
    }
    if data.is_video == true || data.preview?.reddit_video_preview != nil || data.media?.oembed != nil {
      return .video
    }
    if data.post_hint == "link" {
      return .link
    }
    return .image
  }
}

/// One post in the canvas: its picture, or its title when it has none. Opens the post.
struct CanvasTile: View, Equatable {
  static func == (lhs: CanvasTile, rhs: CanvasTile) -> Bool {
    lhs.post.id == rhs.post.id && lhs.size == rhs.size && lhs.showSub == rhs.showSub && lhs.blurNSFW == rhs.blurNSFW && lhs.readOnScroll == rhs.readOnScroll && lhs.theme == rhs.theme
  }

  let post: Post
  let sub: Subreddit
  let size: CGFloat
  let theme: PostLinkTheme
  var showSub = false
  var blurNSFW = true
  var readOnScroll = false

  @Environment(\.navColumn) private var navColumn
  @Environment(\.displayScale) private var displayScale

  private func open() {
    Nav.to(.reddit(.post(post)), from: navColumn)
  }

  var body: some View {
    if let data = post.data {
      Button(action: open) {
        Group {
          if let url = CanvasThumbnail.url(for: data, pixelWidth: size * displayScale) {
            picture(url, data: data)
          } else {
            text(data)
          }
        }
        .frame(width: size, height: size)
        .clipped()
        .overlay { OpenPostHighlight(postID: post.id, cornerRadius: 0, outline: true) }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .contextMenu {
        PostMenuItems(post: post)
      } preview: {
        PostLinkContextPreview(post: post, sub: sub)
      }
      .accessibilityLabel(postTitleAccessibilityLabel(data))
      .accessibilityValue(accessibilityValue(data))
      .accessibilityHint("Opens the post")
      .accessibilityActions { PostMenuItems(post: post) }
      .modifier(ReadOnScrollModifier(post: post, enabled: readOnScroll))
    }
  }

  private func picture(_ url: URL, data: PostData) -> some View {
    let request = ImageRequest(url: url, processors: [ImageProcessors.Resize(size: CGSize(width: size, height: size), unit: .points, contentMode: .aspectFill, crop: true)])
    let hidden = blurNSFW && (data.over_18 == true || data.spoiler == true)
    return LazyImageOpt(request: request, transaction: .init(animation: .default)) { state in
      if let image = state.image {
        image
          .resizable()
          .scaledToFill()
          .accessibilityIgnoresInvertColors()
      } else {
        Color.primary.opacity(0.08)
      }
    }
    .onDisappear(.cancel)
    .frame(width: size, height: size)
    .blur(radius: hidden ? 24 : 0, opaque: true)
    .overlay {
      if hidden {
        Text(data.over_18 == true ? "NSFW" : "Spoiler")
          .font(.caption.weight(.bold))
          .foregroundStyle(.white)
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(Capsule().fill(.black.opacity(0.5)))
      }
    }
    .overlay(alignment: .topTrailing) {
      if let glyph = glyph(CanvasThumbnail.kind(of: data)) {
        glyph
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 6)
          .padding(.vertical, 4)
          .background(Capsule().fill(.black.opacity(0.5)))
          .padding(6)
      }
    }
  }

  private func glyph(_ kind: CanvasThumbnail.Kind) -> Text? {
    switch kind {
    case .image: nil
    case let .gallery(count): Text("\(Image(systemName: "square.on.square")) \(count)")
    case .video: Text(Image(systemName: "play.fill"))
    case .link: Text(Image(systemName: "link"))
    }
  }

  /// Posts without a picture: the title, and the subreddit or the score and comments under it.
  private func text(_ data: PostData) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(data.title)
        .contentFont(15, .semibold, relativeTo: .title)
        .foregroundStyle(theme.titleText.color())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      Group {
        if showSub {
          Text(verbatim: "r/\(data.subreddit)")
        } else {
          Text("\(Image(systemName: "arrow.up")) \(formatBigNumber(data.ups))  \(Image(systemName: "bubble")) \(formatBigNumber(data.num_comments))")
        }
      }
      .contentFont(12, .medium, relativeTo: .meta)
      .foregroundStyle(theme.badge.statsText.color())
      .lineLimit(1)
    }
    .padding(10)
    // A tint over the cell's color sets it apart from the cell-colored feed around it.
    .background(Color.primary.opacity(0.07))
    .background(theme.bg.color())
  }

  private func accessibilityValue(_ data: PostData) -> String {
    var parts: [String] = []
    if showSub {
      parts.append("r/\(data.subreddit)")
    }
    parts.append("\(formatBigNumber(data.ups)) points")
    parts.append("\(formatBigNumber(data.num_comments)) comments")
    return parts.joined(separator: ", ")
  }
}

/// A row of canvas tiles, either side of the hinge when there's one across the grid.
struct CanvasRow<Tile: View>: View {
  let posts: ArraySlice<Post>
  let grid: CanvasGrid
  @ViewBuilder let tile: (Post) -> Tile

  var body: some View {
    if let hinge = grid.hinge {
      HStack(spacing: 0) {
        tiles(posts.prefix(hinge.columnsBefore))
          .frame(width: hinge.leadingWidth)
        Color.clear
          .frame(width: hinge.width)
        tiles(posts.dropFirst(hinge.columnsBefore))
          .frame(maxWidth: .infinity)
      }
    } else {
      tiles(posts)
        .frame(maxWidth: .infinity)
    }
  }

  /// Leading-aligned, so a last row that isn't full starts at the edge.
  private func tiles(_ posts: ArraySlice<Post>) -> some View {
    let count = grid.hinge?.columnsBefore ?? grid.columns
    let width = grid.tileSize * CGFloat(count) + CanvasGrid.spacing * CGFloat(count - 1)
    return HStack(spacing: CanvasGrid.spacing) {
      ForEach(posts, id: \.id) { post in
        tile(post)
      }
    }
    .frame(width: width, alignment: .leading)
  }
}
