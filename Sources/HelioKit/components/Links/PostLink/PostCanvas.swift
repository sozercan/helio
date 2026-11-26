import Nuke
import SwiftUI

struct CanvasGrid: Equatable {
  static let minTileWidth: CGFloat = 150
  static let spacing: CGFloat = 2

  struct Hinge: Equatable {
    let columnsBefore: Int
    let leadingWidth: CGFloat
    let width: CGFloat
  }

  let columns: Int
  let tileSize: CGFloat
  let hinge: Hinge?

  init(width: CGFloat, division: ClosedRange<CGFloat>? = nil) {
    let spacing = Self.spacing
    func fitting(_ width: CGFloat) -> Int {
      max(1, Int(((width + spacing) / (Self.minTileWidth + spacing)).rounded(.down)))
    }
    func tile(_ width: CGFloat, _ columns: Int) -> CGFloat {
      max(0, ((width - spacing * CGFloat(columns - 1)) / CGFloat(columns)).rounded(.down))
    }
    if let division, division.lowerBound > 0, division.upperBound < width {
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

  func rows<T>(_ items: [T]) -> [ArraySlice<T>] {
    stride(from: 0, to: items.count, by: columns).map { items[$0 ..< min($0 + columns, items.count)] }
  }
}

enum CanvasThumbnail {
  enum Kind: Equatable {
    case image, gallery(Int), video, link
  }

  static func url(for data: PostData, pixelWidth: CGFloat) -> URL? {
    let data = data.crosspost_parent_list?.first ?? data
    guard !data.is_self else { return nil }
    if data.is_gallery == true, let first = data.gallery_data?.items?.first, case let item?? = data.media_metadata?[first.media_id] {
      let sizes = (item.p ?? []) + [item.s].compactMap(\.self)
      if let url = smallest(sizes.map { (min($0.x, $0.y), $0.u) }, covering: pixelWidth) {
        return url
      }
    }
    if let image = data.preview?.images?.first {
      let sizes = (image.resolutions ?? []) + [image.source].compactMap(\.self)
      if let url = smallest(sizes.map { (min($0.width ?? 0, $0.height ?? $0.width ?? 0), $0.url) }, covering: pixelWidth) {
        return url
      }
    }
    if let thumbnail = data.media?.oembed?.thumbnail_url {
      return URL(string: thumbnail.escape)
    }
    if let direct = directImageURL(data) {
      return direct
    }
    if let thumbnail = data.thumbnail, let url = URL(string: thumbnail.escape), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false {
      return url
    }
    return nil
  }

  static func smallest(_ sizes: [(shorterSide: Int, url: String?)], covering pixelWidth: CGFloat) -> URL? {
    let usable = sizes.compactMap { size in size.url.flatMap { URL(string: $0.escape) }.map { (size.shorterSide, $0) } }
      .sorted { $0.0 < $1.0 }
    return (usable.first { CGFloat($0.0) >= pixelWidth } ?? usable.last)?.1
  }

  enum Veil: Equatable {
    case nsfw, spoiler
  }

  static func accessibilityLabel(for data: PostData) -> String {
    let posts = [data] + (data.crosspost_parent_list?.prefix(1) ?? [])
    var parts = [data.title]
    if posts.contains(where: { $0.over_18 == true }) {
      parts.append(String(localized: "NSFW"))
    }
    if posts.contains(where: { $0.spoiler == true }) {
      parts.append(String(localized: "Spoiler"))
    }
    if let flair = flairWithoutEmojis(str: data.link_flair_text)?.joined(separator: " "), !flair.isEmpty {
      parts.append(flair)
    }
    return parts.joined(separator: ", ")
  }

  static func veil(for data: PostData) -> Veil? {
    let posts = [data] + (data.crosspost_parent_list?.prefix(1) ?? [])
    if posts.contains(where: { $0.over_18 == true }) {
      return .nsfw
    }
    if posts.contains(where: { $0.spoiler == true }) {
      return .spoiler
    }
    return nil
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

struct CanvasTile: View, Equatable {
  static func == (lhs: CanvasTile, rhs: CanvasTile) -> Bool {
    lhs.post === rhs.post && lhs.sub === rhs.sub && lhs.size == rhs.size && lhs.showSub == rhs.showSub && lhs.blurNSFW == rhs.blurNSFW && lhs.readOnScroll == rhs.readOnScroll && lhs.theme == rhs.theme
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
      .accessibilityLabel(CanvasThumbnail.accessibilityLabel(for: data))
      .accessibilityValue(accessibilityValue(data))
      .accessibilityHint("Opens the post")
      .accessibilityActions { PostMenuItems(post: post) }
      .modifier(OpenPostSelectedTrait(postID: post.id, marks: true))
      .modifier(ReadOnScrollModifier(post: post, enabled: readOnScroll))
    }
  }

  private func picture(_ url: URL, data: PostData) -> some View {
    let request = ImageRequest(url: url, processors: [ImageProcessors.Resize(size: CGSize(width: size, height: size), unit: .points, contentMode: .aspectFill, crop: true)])
    let veil = blurNSFW ? CanvasThumbnail.veil(for: data) : nil
    let hidden = veil != nil
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
        Text(veil == .nsfw ? "NSFW" : "Spoiler")
          .font(.caption.weight(.bold))
          .foregroundStyle(.white)
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(Capsule().fill(.black))
      }
    }
    .overlay(alignment: .topTrailing) {
      if let glyph = glyph(CanvasThumbnail.kind(of: data)) {
        glyph
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 6)
          .padding(.vertical, 4)
          .background(Capsule().fill(.black))
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
