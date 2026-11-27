import Alamofire
import Foundation
import Nuke
import NukeUI
import SwiftUI
import YouTubePlayerKit

struct ImgExtracted: Equatable, Identifiable {
  static func == (lhs: ImgExtracted, rhs: ImgExtracted) -> Bool {
    lhs.id == rhs.id && lhs.size == rhs.size
  }

  let url: URL
  let size: CGSize
  let request: ImageRequest
  var posterURL: URL?
  var id: String {
    self.url.absoluteString
  }
}

struct YTMediaExtracted: Equatable, Identifiable {
  static func == (lhs: YTMediaExtracted, rhs: YTMediaExtracted) -> Bool {
    lhs.id == rhs.id
  }

  let videoID: String
  let size: CGSize
  let thumbnailURL: URL
  let thumbnailRequest: ImageRequest
  let player: YouTubePlayer
  let author: String
  let authorURL: URL
  var id: String {
    self.videoID
  }
}

struct EntityExtracted<T: GenericRedditEntityDataType, B: Hashable>: Equatable {
  static func == (lhs: EntityExtracted, rhs: EntityExtracted) -> Bool {
    lhs.entity == rhs.entity
  }

  var subredditID: String?
  var postID: String?
  var commentID: String?
  var userID: String?
  let entity: GenericRedditEntity<T, B>
}

struct StreamableExtracted: Equatable {
  let shortCode: String
  init(url: String) {
    self.shortCode = String(url[url.index(url.lastIndex(of: "/") ?? url.startIndex, offsetBy: 1)...])
  }
}

struct StreamableCached: Equatable {
  let url: URL
  let size: CGSize
}

enum MediaExtractedType: Equatable {
  case link(PreviewModel)
  case video(SharedVideo)
  case imgs([ImgExtracted])
  case yt(YTMediaExtracted)
  case streamable(StreamableExtracted)
  case repost(Post)
  case post(EntityExtracted<PostData, PostHelioData>?)
  case comment(EntityExtracted<CommentData, CommentHelioData>?)
  case subreddit(EntityExtracted<SubredditData, AnyHashable>?)
  case user(EntityExtracted<UserData, AnyHashable>?)
}

extension MediaExtractedType {
  func isTappableInFeed(mediaTappable: Bool, compact: Bool) -> Bool {
    switch self {
    case .link, .post, .subreddit, .user: true
    case .comment: compact || mediaTappable
    default: mediaTappable
    }
  }

  func loadLinkedEntity() {
    switch self {
    case let .post(extracted): extracted?.entity.fetchItself()
    case let .comment(extracted): extracted?.entity.fetchItself()
    case let .user(extracted): extracted?.entity.fetchItself()
    case let .subreddit(extracted):
      if let sub = extracted?.entity {
        Task(priority: .utility) {
          await sub.loadIfNeeded()
        }
      }
    default: break
    }
  }
}

func decodingFilling(_ side: Double) -> ImageRequest.ThumbnailOptions {
  ImageRequest.ThumbnailOptions(size: CGSize(width: side, height: side), unit: .points, contentMode: .aspectFill)
}

func singleImageProcessing(compact: Bool, contentWidth: Double, url: URL, knownSize: Bool = true, compactThumbnailsGIFs: Bool = false) -> (processors: [ImageProcessing], userInfo: [ImageRequest.UserInfoKey: Any]) {
  guard contentWidth > 0 || compact else { return ([], [:]) }
  guard compact else {
    guard knownSize else {
      let square = CGSize(width: contentWidth, height: contentWidth)
      let processors: [ImageProcessing] = [ImageProcessors.Resize(size: square, unit: .points, contentMode: .aspectFill, crop: false, upscale: true)]
      return (processors, url.isGIF ? [:] : [.thumbnailKey: decodingFilling(contentWidth)])
    }
    let processors: [ImageProcessing] = [ImageProcessors.Resize(width: contentWidth, unit: .points, upscale: true)]
    guard !url.isGIF else { return (processors, [:]) }
    return (processors, [.thumbnailKey: ImageRequest.ThumbnailOptions(size: CGSize(width: contentWidth, height: 1_000_000), unit: .points, contentMode: .aspectFit)])
  }
  let square = CGSize(width: scaledCompactModeThumbSize(), height: scaledCompactModeThumbSize())
  let processors: [ImageProcessing] = contentWidth == 0 ? [] : [ImageProcessors.Resize(size: square, unit: .points, contentMode: .aspectFill, crop: false, upscale: true)]
  guard compactThumbnailsGIFs || !url.isGIF else { return (processors, [:]) }
  return (processors, [.thumbnailKey: ImageRequest.ThumbnailOptions(size: square, unit: .points, contentMode: .aspectFill)])
}

func mediaExtractor(compact: Bool, contentWidth: Double = .screenW, _ data: PostData, theme: HelioTheme? = nil, fetchLinkMetadata: Bool = true) -> MediaExtractedType? {
  guard !data.is_self else { return nil }

  if let postEmbed = data.crosspost_parent_list?.first {
    return .repost(Post(data: postEmbed, contentWidth: contentWidth, secondary: true, theme: theme, fetchAvatar: false, fetchLinkMetadata: fetchLinkMetadata))
  }

  let contentWidth = contentWidth - ((theme?.postLinks.theme.innerPadding.horizontal ?? 0) * 2) - ((theme?.postLinks.theme.outerHPadding ?? 0) * 2)

  if let gallery = extractGalleryImages(data, compact: compact, contentWidth: contentWidth) {
    return .imgs(gallery)
  }

  if let videoPreview = data.preview?.reddit_video_preview, let videoURL = (videoPreview.hls_url ?? videoPreview.fallback_url).flatMap(URL.init(string:)) {
    return .video(SharedVideo.get(url: videoURL, size: videoSize(data, width: videoPreview.width, height: videoPreview.height), posterURL: previewPosterURL(data), dashURL: videoPreview.dash_url.flatMap(URL.init(string:)), fallbackURL: videoPreview.fallback_url.flatMap(URL.init(string:))))
  }

  if let redditVideo = data.media?.reddit_video, let videoURL = (redditVideo.hls_url ?? redditVideo.fallback_url).flatMap(URL.init(string:)) {
    return .video(SharedVideo.get(url: videoURL, size: videoSize(data, width: redditVideo.width.map(Double.init), height: redditVideo.height.map(Double.init)), posterURL: previewPosterURL(data), dashURL: redditVideo.dash_url.flatMap(URL.init(string:)), fallbackURL: redditVideo.fallback_url.flatMap(URL.init(string:))))
  }

  if data.media?.type == "youtube.com", let oembed = data.media?.oembed, let html = oembed.html, let ytID = extractYoutubeIdFromOEmbed(html), let thumbURL = oembed.thumbnail_url.flatMap(URL.init(string:)) ?? URL(string: "https://i.ytimg.com/vi/\(ytID)/hqdefault.jpg"), let watchURL = URL(string: "https://www.youtube.com/watch?v=\(ytID)") {
    let thumbReq = youTubeThumbnailRequest(thumbURL, contentWidth: contentWidth, theme: theme)
    let size = CGSize(width: CGFloat(oembed.width ?? 16), height: CGFloat(oembed.height ?? 9))
    let newExtracted = YTMediaExtracted(videoID: ytID, size: size, thumbnailURL: thumbURL, thumbnailRequest: thumbReq, player: YouTubePlayer(source: .video(id: ytID)), author: oembed.author_name ?? "", authorURL: oembed.author_url.flatMap(URL.init(string:)) ?? watchURL)
    return .yt(newExtracted)
  }

  if let url = directImageURL(data) {
    var actualWidth = 0
    var actualHeight = 0
    if let images = data.preview?.images, !images.isEmpty, let image = images[0].source, let width = image.width, let height = image.height {
      actualWidth = width
      actualHeight = height
    }

    let (processors, userInfo) = singleImageProcessing(compact: compact, contentWidth: contentWidth, url: url, knownSize: actualWidth > 0 && actualHeight > 0)
    let posterURL = url.isGIF ? previewPosterURL(data) : nil
    let imgExtracted = ImgExtracted(url: url, size: CGSize(width: actualWidth, height: actualHeight), request: ImageRequest(url: url, processors: processors + [ImageProcessors.ScaleFixer()], userInfo: userInfo), posterURL: posterURL)
    return .imgs([imgExtracted])
  }

  if let images = data.preview?.images, !images.isEmpty, let image = images[0].source, let rawSrc = image.url, !rawSrc.contains("external-preview"), let imgURL = rootURL(rawSrc.replacing("/preview.", with: "/i.").escape) ?? loadableMediaURL(rawSrc.escape), let width = image.width, let height = image.height {
    let (processors, userInfo) = singleImageProcessing(compact: compact, contentWidth: contentWidth, url: imgURL, compactThumbnailsGIFs: true)
    let imgExtracted = ImgExtracted(url: imgURL, size: CGSize(width: width, height: height), request: ImageRequest(url: imgURL, processors: processors + [ImageProcessors.ScaleFixer()], userInfo: userInfo))
    return .imgs([imgExtracted])
  }

  if VIDEOS_FORMATS.contains(where: { data.url.hasSuffix($0) }), let url = URL(string: data.url) {
    return .video(SharedVideo.get(url: url, size: videoSize(data, width: nil, height: nil), posterURL: previewPosterURL(data)))
  }

  if data.url.contains("streamable.com") {
    return .streamable(StreamableExtracted(url: data.url))
  }

  if let redditEntity = extractLinkedRedditEntity(data, compact: compact, fetchLinkMetadata: fetchLinkMetadata) {
    return redditEntity
  }

  if data.post_hint == "link" || !data.domain.isEmpty, let linkURL = URL(string: data.url) {
    return .link(PreviewModel.shared(linkURL, compact: compact, fetch: fetchLinkMetadata))
  }

  return nil
}

extension URL {
  var isGIF: Bool {
    pathExtension.lowercased() == "gif"
  }
}

private func extractLinkedRedditEntity(_ data: PostData, compact: Bool, fetchLinkMetadata: Bool) -> MediaExtractedType? {
  let actualURL = data.url.hasPrefix("/r/") || data.url.hasPrefix("/u/") ? "https://reddit.com\(data.url)" : data.url
  guard let urlComponents = URLComponents(string: actualURL) else {
    return nil
  }
  let pathComponents = urlComponents.path.components(separatedBy: "/").filter { !$0.isEmpty }
  func linked(_ media: MediaExtractedType) -> MediaExtractedType {
    if fetchLinkMetadata {
      media.loadLinkedEntity()
    }
    return media
  }
  guard urlComponents.host?.hasSuffix("reddit.com") == true, pathComponents.count > 1 else {
    return nil
  }
  switch pathComponents[0] {
  case "r":
    let subredditName = pathComponents[1]
    if pathComponents.count > 2, pathComponents[2] == "comments" {
      let postId = pathComponents[3]
      if pathComponents.count >= 6 {
        let commentId = pathComponents[5]
        let comment = Comment(id: commentId, typePrefix: Comment.prefix)
        return linked(.comment(EntityExtracted(subredditID: subredditName, postID: postId, commentID: commentId, entity: comment)))
      }
      let post = Post(id: postId, typePrefix: Post.prefix)
      return linked(.post(EntityExtracted(subredditID: subredditName, postID: postId, entity: post)))
    }
    let sub = Subreddit(id: subredditName)
    return linked(.subreddit(EntityExtracted(subredditID: subredditName, entity: sub)))

  case "user", "u":
    let username = pathComponents[1]
    let user = User(id: username, typePrefix: User.prefix)
    return linked(.user(EntityExtracted(userID: username, entity: user)))

  default:
    if !data.is_self, let linkURL = URL(string: data.url) {
      return .link(PreviewModel.shared(linkURL, compact: compact, fetch: fetchLinkMetadata))
    }
    return nil
  }
}

private func extractGalleryImages(_ data: PostData, compact: Bool, contentWidth: Double) -> [ImgExtracted]? {
  guard data.is_gallery == true, let galleryData = data.gallery_data?.items, let metadata = data.media_metadata else {
    return nil
  }
  let halfWidth = (contentWidth - ImageMediaPost.gallerySpacing) / 2
  let sizes = [
    1: [0: contentWidth],
    2: [0: halfWidth, 1: halfWidth],
    3: [0: halfWidth, 1: halfWidth, 2: contentWidth],
  ]
  let thumbnailInfo = galleryThumbnailInfo(from: data.thumbnail)
  let fallbackExtension = if let ext = thumbnailInfo?.extension, ext != "gif" {
    ext
  } else {
    "jpeg"
  }

  let galleryArr = Array(galleryData.enumerated()).compactMap { i, item -> ImgExtracted? in
    let id = item.media_id
    guard case let .some(itemMeta?) = metadata[id], let resolved = resolvedGalleryImage(
      mediaID: id,
      itemMeta: itemMeta,
      thumbnailInfo: thumbnailInfo,
      fallbackExtension: fallbackExtension,
    ) else { return nil }

    let actualWidth = sizes[galleryData.count]?[i] ?? halfWidth
    let sizeSimple = compact ? scaledCompactModeThumbSize() : actualWidth
    let processors: [ImageProcessing] = contentWidth == 0 ? [] : [ImageProcessors.Resize(size: .init(width: sizeSimple, height: sizeSimple), unit: .points, contentMode: .aspectFill, crop: false, upscale: true)]
    var userInfo: [ImageRequest.UserInfoKey: Any] = [:]
    if compact, !resolved.url.isGIF {
      userInfo[.thumbnailKey] = ImageRequest.ThumbnailOptions(size: .init(width: scaledCompactModeThumbSize(), height: scaledCompactModeThumbSize()), unit: .points, contentMode: .aspectFill)
    } else if contentWidth != 0, !resolved.url.isGIF {
      userInfo[.thumbnailKey] = decodingFilling(sizeSimple)
    }
    return ImgExtracted(url: resolved.url, size: resolved.size, request: ImageRequest(url: resolved.url, processors: processors + [ImageProcessors.ScaleFixer()], userInfo: userInfo))
  }
  return galleryArr.isEmpty ? nil : galleryArr
}

private let galleryImageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp"]

private func isPlainRedditMediaID(_ mediaID: String) -> Bool {
  !mediaID.isEmpty && mediaID.count <= 64 && mediaID.unicodeScalars.allSatisfy {
    ("a" ... "z").contains($0) || ("A" ... "Z").contains($0) || ("0" ... "9").contains($0)
  }
}

private func galleryThumbnailInfo(from thumbnail: String?) -> (mediaID: String, extension: String)? {
  guard
    let thumbnail,
    let url = URL(string: thumbnail.escape),
    let host = url.host?.lowercased(),
    host == "preview.redd.it" || host == "i.redd.it"
  else { return nil }
  let filename = url.lastPathComponent
  let ext = url.pathExtension.lowercased()
  guard galleryImageExtensions.contains(ext) else { return nil }
  let mediaID = (filename as NSString).deletingPathExtension
  guard isPlainRedditMediaID(mediaID) else { return nil }
  return (mediaID, ext)
}

private func isRedditHostedGIFMetadata(mediaID: String, item: MediaMetadataItem) -> Bool {
  guard !mediaID.isEmpty, !mediaID.hasPrefix("giphy|") else { return false }
  if item.m?.lowercased() == "image/gif" || item.e == "AnimatedImage" {
    return true
  }
  let sourceURLs = [item.s?.gif, item.s?.mp4, item.s?.u].compactMap { $0?.lowercased() }
  return sourceURLs.contains { url in
    (url.contains("i.redd.it") && url.hasSuffix(".gif")) || (url.contains("preview.redd.it") && url.contains("format=mp4"))
  }
}

private func resolvedGalleryImage(
  mediaID: String,
  itemMeta: MediaMetadataItem,
  thumbnailInfo: (mediaID: String, extension: String)?,
  fallbackExtension: String,
) -> (url: URL, size: CGSize)? {
  if let extArr = itemMeta.m?.split(separator: "/"), let rawExt = extArr.last, !rawExt.isEmpty, let size = itemMeta.s, let imgURL = URL(string: "https://i.redd.it/\(mediaID).\(rawExt)") {
    return (imgURL, CGSize(width: size.x, height: size.y))
  }

  if isRedditHostedGIFMetadata(mediaID: mediaID, item: itemMeta), isPlainRedditMediaID(mediaID), let gifURL = URL(string: "https://i.redd.it/\(mediaID).gif") {
    let size = itemMeta.s.map { CGSize(width: $0.x, height: $0.y) } ?? .zero
    return (gifURL, size)
  }

  guard itemMeta.status.lowercased() == "failed", isPlainRedditMediaID(mediaID) else {
    return nil
  }
  let ext = (thumbnailInfo?.mediaID == mediaID ? thumbnailInfo?.extension : nil) ?? fallbackExtension
  guard let imgURL = URL(string: "https://i.redd.it/\(mediaID).\(ext)") else {
    return nil
  }
  return (imgURL, .zero)
}

func directImageURL(_ data: PostData) -> URL? {
  guard let url = URL(string: data.url.escape), IMAGES_FORMATS.contains(".\(url.pathExtension.lowercased())") else { return nil }
  return loadableMediaURL(url)
}

func youTubeThumbnailRequest(_ url: URL, contentWidth: Double, theme: HelioTheme?) -> ImageRequest {
  ImageRequest(url: url, processors: [.resize(width: getPostContentWidth(contentWidth: contentWidth, theme: theme))], priority: .normal)
}

func previewPosterURL(_ data: PostData) -> URL? {
  data.preview?.images?.first?.source?.url.flatMap { loadableMediaURL($0.escape) }
}

private func videoSize(_ data: PostData, width: Double?, height: Double?) -> CGSize {
  if let width, let height, width > 0, height > 0 {
    return CGSize(width: width, height: height)
  }
  let source = data.preview?.images?.first?.source
  return CGSize(width: source?.width ?? 0, height: source?.height ?? 0)
}

private func loadableMediaURL(_ url: URL) -> URL {
  guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
        let items = components.queryItems, !items.isEmpty else { return url }
  let kept = items.filter { !isTrackingParameter($0.name) }
  guard kept.count < items.count else { return url }
  components.queryItems = kept.isEmpty ? nil : kept
  return components.url ?? url
}

private func isTrackingParameter(_ name: String) -> Bool {
  let name = name.lowercased()
  return name.hasPrefix("utm_") || ["fbclid", "gclid", "igshid", "mc_cid", "mc_eid", "ref", "ref_src"].contains(name)
}

private func loadableMediaURL(_ string: String) -> URL? {
  URL(string: string).map(loadableMediaURL)
}

private func extractYoutubeIdFromOEmbed(_ text: String) -> String? {
  let pattern = "(?<=www\\.youtube\\.com/embed/)[A-Za-z0-9_-]+"
  let regex = try? NSRegularExpression(pattern: pattern)
  return regex?.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)).map {
    String(text[Range($0.range, in: text)!])
  }
}

struct StreamableAPIResponse: Codable {
  let files: StreamableAPIFiles?
}

struct StreamableAPIFiles: Codable {
  let mp4: StreamableAPIFile?
  let mp4Mobile: StreamableAPIFile?

  enum CodingKeys: String, CodingKey {
    case mp4
    case mp4Mobile = "mp4-mobile"
  }
}

struct StreamableAPIFile: Codable {
  let url: String
  let width: Int
  let height: Int
}
