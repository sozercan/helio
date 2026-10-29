//
//  mediaExtractor.swift
//  Helio
//
//  Created by Igor Marcossi on 21/08/23.
//

import Foundation
import SwiftUI
import NukeUI
import Nuke
import YouTubePlayerKit
import Alamofire

struct ImgExtracted: Equatable, Identifiable {
  static func == (lhs: ImgExtracted, rhs: ImgExtracted) -> Bool {
    lhs.id == rhs.id && lhs.size == rhs.size
  }
  
  let url: URL
  let size: CGSize
  let request: ImageRequest
  /// Static preview shown while an animated image loads.
  var posterURL: URL? = nil
  var id: String { self.url.absoluteString }
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
  var id: String { self.videoID }
}

struct EntityExtracted<T: GenericRedditEntityDataType, B: Hashable>: Equatable {
  static func == (lhs: EntityExtracted, rhs: EntityExtracted) -> Bool {
    lhs.entity == rhs.entity
  }
  var subredditID: String? = nil
  var postID: String? = nil
  var commentID: String? = nil
  var userID: String? = nil
  let entity: GenericRedditEntity<T, B>
}

struct StreamableExtracted: Equatable {
  static func == (lhs: StreamableExtracted, rhs: StreamableExtracted) -> Bool {
    lhs.shortCode == rhs.shortCode
  }
  
  let shortCode: String
  init(url: String) {
    self.shortCode = String(url[url.index(url.lastIndex(of: "/") ?? url.startIndex, offsetBy: 1)...])
  }
}

struct StreamableCached: Equatable {
  static func == (lhs: StreamableCached, rhs: StreamableCached) -> Bool {
    lhs.url == rhs.url && lhs.size == rhs.size
  }
  
  let url: URL
  let size: CGSize
  
  init(url: URL, size: CGSize) {
    self.url = url
    self.size = size
  }
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


// ORDER MATTERS!
func mediaExtractor(compact: Bool, contentWidth: Double = .screenW, _ data: PostData, theme: HelioTheme? = nil) -> MediaExtractedType? {
  guard !data.is_self else { return nil }

  let contentWidth = contentWidth - ((theme?.postLinks.theme.innerPadding.horizontal ?? 0) * 2) - ((theme?.postLinks.theme.outerHPadding ?? 0) * 2)
  
  // A crosspost's own url and media describe the original post's media (often a bare
  // v.redd.it link with no `media`), which can't be played from here. Show the original.
  if let postEmbed = data.crosspost_parent_list?.first {
    return .repost(Post(data: postEmbed, contentWidth: contentWidth, secondary: true, theme: theme))
  }
  
  if let is_gallery = data.is_gallery, is_gallery, let galleryData = data.gallery_data?.items, let metadata = data.media_metadata {
    
    let halfWidth = (contentWidth - ImageMediaPost.gallerySpacing) / 2
    let sizes = [
      1: [0: contentWidth],
      2: [0: halfWidth, 1: halfWidth],
      3: [0: halfWidth, 1: halfWidth, 2: contentWidth]
    ]
    
    let galleryArr = Array(galleryData.enumerated()).compactMap { i, item in
      let id = item.media_id
      if let itemMeta = metadata[String(id)], let extArr = itemMeta?.m?.split(separator: "/"), let size = itemMeta?.s, let imgURL = URL(string: "https://i.redd.it/\(id).\(extArr[extArr.count - 1])") {
        
        var actualWidth = contentWidth
        if let sizeInstructions = sizes[galleryData.count], let mySize = sizeInstructions[i] { actualWidth = mySize } else { actualWidth = halfWidth }
        
        let sizeSimple = compact ? scaledCompactModeThumbSize() : actualWidth
        let processors: [ImageProcessing] = contentWidth == 0 ? [] : [ImageProcessors.Resize(size: .init(width: sizeSimple, height: sizeSimple), unit: .points, contentMode: .aspectFill, crop: false, upscale: true)]
        var userInfo: [ImageRequest.UserInfoKey : Any] = [:]
        if compact && !imgURL.isGIF {
          userInfo[.thumbnailKey] = ImageRequest.ThumbnailOptions(size: .init(width: scaledCompactModeThumbSize(), height: scaledCompactModeThumbSize()), unit: .points, contentMode: .aspectFill)
        }
        return ImgExtracted(url: imgURL, size: CGSize(width: size.x, height: size.y), request: ImageRequest(url: imgURL, processors: processors + [ImageProcessors.ScaleFixer()], userInfo: userInfo))
      }
      return nil
    }
    // If no item had usable metadata, fall through instead of showing an empty gallery.
    if !galleryArr.isEmpty {
      return .imgs(galleryArr)
    }
  }
  
  // Prefer the HLS stream, but play the MP4 fallback when Reddit omits it.
  if let videoPreview = data.preview?.reddit_video_preview, let videoURL = (videoPreview.hls_url ?? videoPreview.fallback_url).flatMap(URL.init(string:)) {
    return .video(SharedVideo.get(url: videoURL, size: videoSize(data, width: videoPreview.width, height: videoPreview.height), posterURL: previewPosterURL(data)))
  }
  
  if let redditVideo = data.media?.reddit_video, let videoURL = (redditVideo.hls_url ?? redditVideo.fallback_url).flatMap(URL.init(string:)) {
    return .video(SharedVideo.get(url: videoURL, size: videoSize(data, width: redditVideo.width.map(Double.init), height: redditVideo.height.map(Double.init)), posterURL: previewPosterURL(data)))
  }
  
  // Only the video id is required; the rest of the oEmbed payload is often missing.
  if data.media?.type == "youtube.com", let oembed = data.media?.oembed, let html = oembed.html, let ytID = extractYoutubeIdFromOEmbed(html), let thumbURL = oembed.thumbnail_url.flatMap(URL.init(string:)) ?? URL(string: "https://i.ytimg.com/vi/\(ytID)/hqdefault.jpg"), let watchURL = URL(string: "https://www.youtube.com/watch?v=\(ytID)") {
    let thumbReq = youTubeThumbnailRequest(thumbURL, contentWidth: contentWidth, theme: theme)
    let size = CGSize(width: CGFloat(oembed.width ?? 16), height: CGFloat(oembed.height ?? 9))
    let newExtracted = YTMediaExtracted(videoID: ytID, size: size, thumbnailURL: thumbURL, thumbnailRequest: thumbReq, player: YouTubePlayer(source: .video(id: ytID)), author: oembed.author_name ?? "", authorURL: oembed.author_url.flatMap(URL.init(string:)) ?? watchURL)
    return .yt(newExtracted)
  }
  
  if let rawImageURL = URL(string: data.url.escape), IMAGES_FORMATS.contains(".\(rawImageURL.pathExtension.lowercased())") {
    let url = loadableMediaURL(rawImageURL)
    var actualWidth = 0
    var actualHeight = 0
    if let images = data.preview?.images, images.count > 0, let image = images[0].source, let width = image.width, let height = image.height {
      actualWidth = width
      actualHeight = height
    }
    
    let size = compact ? scaledCompactModeThumbSize() : contentWidth
    let processors: [ImageProcessing] = contentWidth == 0 ? [] : [ImageProcessors.Resize(size: CGSize(width: size, height: size), unit: .points, contentMode: .aspectFill, crop: false, upscale: true)]
    var userInfo: [ImageRequest.UserInfoKey : Any] = [:]
    if compact && !url.isGIF {
      userInfo[.thumbnailKey] = ImageRequest.ThumbnailOptions(size: .init(width: scaledCompactModeThumbSize(), height: scaledCompactModeThumbSize()), unit: .points, contentMode: .aspectFill)
    }
    let posterURL = url.isGIF ? previewPosterURL(data) : nil
    let imgExtracted = ImgExtracted(url: url, size: CGSize(width: actualWidth, height: actualHeight), request: ImageRequest(url: url, processors: processors + [ImageProcessors.ScaleFixer()], userInfo: userInfo), posterURL: posterURL)
    return .imgs([imgExtracted])
  }
  
  // Prefer the full-size i.redd.it image, falling back to the (signed) preview URL.
  if let images = data.preview?.images, images.count > 0, let image = images[0].source, let rawSrc = image.url, !rawSrc.contains("external-preview"), let imgURL = rootURL(rawSrc.replacing("/preview.", with: "/i.").escape) ?? loadableMediaURL(rawSrc.escape), let width = image.width, let height = image.height {
    
    let size = compact ? scaledCompactModeThumbSize() : contentWidth
    let processors: [ImageProcessing] = contentWidth == 0 ? [] : [ImageProcessors.Resize(size: CGSize(width: size, height: size), unit: .points, contentMode: .aspectFill, crop: false, upscale: true)]
    var userInfo: [ImageRequest.UserInfoKey : Any] = [:]
    if compact {
      userInfo[.thumbnailKey] = ImageRequest.ThumbnailOptions(size: .init(width: scaledCompactModeThumbSize(), height: scaledCompactModeThumbSize()), unit: .points, contentMode: .aspectFill)
    }
    let imgExtracted = ImgExtracted(url: imgURL, size: CGSize(width: width, height: height), request: ImageRequest(url: imgURL, processors: processors + [ImageProcessors.ScaleFixer()], userInfo: userInfo))
    return .imgs([imgExtracted])
  }
  
  if VIDEOS_FORMATS.contains(where: { data.url.hasSuffix($0) }), let url = URL(string: data.url) {
    return .video(SharedVideo.get(url: url, size: videoSize(data, width: nil, height: nil), posterURL: previewPosterURL(data)))
  }
  
  if data.url.contains("streamable.com") {
    return .streamable(StreamableExtracted(url: data.url))
  }
  
  let actualURL = data.url.hasPrefix("/r/") || data.url.hasPrefix("/u/") ? "https://reddit.com\(data.url)" : data.url
  guard let urlComponents = URLComponents(string: actualURL) else {
    return nil
  }
  
  let pathComponents = urlComponents.path.components(separatedBy: "/").filter({ !$0.isEmpty })
  
  if urlComponents.host?.hasSuffix("reddit.com") == true, pathComponents.count > 1 {
    switch pathComponents[0] {
    case "r":
      let subredditName = pathComponents[1]
      if pathComponents.count > 2 && pathComponents[2] == "comments" {
        let postId = pathComponents[3]
        if pathComponents.count >= 6 {
          let commentId = pathComponents[5]
          let comment = Comment(id: commentId, typePrefix: Comment.prefix)
          comment.fetchItself()
          let entityExtracted = EntityExtracted(subredditID: subredditName, postID: postId, commentID: commentId, entity: comment)
          return .comment(entityExtracted)
        }
        let post = Post(id: postId, typePrefix: Post.prefix)
        post.fetchItself()
        let entityExtracted = EntityExtracted(subredditID: subredditName, postID: postId, entity: post)
        return .post(entityExtracted)
//        return .post(id: postId, subreddit: subredditName)
      }
      let sub = Subreddit(id: subredditName)
      Task(priority: .background) {
        await sub.refreshSubreddit()
      }
      let entityExtracted = EntityExtracted(subredditID: subredditName, entity: sub)
      return .subreddit(entityExtracted)
      
    case "user", "u":
      let username = pathComponents[1]
      let user = User(id: username, typePrefix: User.prefix)
      user.fetchItself()
      let entityExtracted = EntityExtracted(userID: username, entity: user)
      return .user(entityExtracted)
//      return .user(username: username)
      
    default:
      if !data.is_self, let linkURL = URL(string: data.url) {
        return .link(PreviewModel(linkURL, compact: compact))
      }
    }
  }
  
  if data.post_hint == "link" || !data.domain.isEmpty, let linkURL = URL(string: data.url) {
    return .link(PreviewModel(linkURL, compact: compact))
  }
  
  return nil
}

extension URL {
  /// By path extension, so signed URLs (`….gif?s=…`) and `.GIF` count too.
  var isGIF: Bool { pathExtension.lowercased() == "gif" }
}

/// A YouTube embed's thumbnail, downsampled for the column.
func youTubeThumbnailRequest(_ url: URL, contentWidth: Double, theme: HelioTheme?) -> ImageRequest {
  ImageRequest(url: url, processors: [.resize(width: getPostContentWidth(contentWidth: contentWidth, theme: theme))], priority: .normal)
}

/// Reddit's static preview of a post, used as a poster while its video or GIF loads.
func previewPosterURL(_ data: PostData) -> URL? {
  data.preview?.images?.first?.source?.url.flatMap { loadableMediaURL($0.escape) }
}

/// The video's own size, or the preview image's when Reddit leaves it out.
private func videoSize(_ data: PostData, width: Double?, height: Double?) -> CGSize {
  if let width, let height, width > 0, height > 0 { return CGSize(width: width, height: height) }
  let source = data.preview?.images?.first?.source
  return CGSize(width: source?.width ?? 0, height: source?.height ?? 0)
}

/// Drops tracking parameters and keeps the rest of the query: signed images (Reddit's
/// previews, CDNs with tokens) only load with theirs.
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
  // Only ID characters: without a query, the URL is followed by a quote and the rest of the HTML.
  let pattern = "(?<=www\\.youtube\\.com/embed/)[A-Za-z0-9_-]+"
  let regex = try? NSRegularExpression(pattern: pattern)
  return regex?.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)).map {
    String(text[Range($0.range, in: text)!])
  }
}

struct StreamableAPIParams: Codable {}
          
struct StreamableAPIResponse: Codable {
  let files: StreamableAPIFiles?
}

struct StreamableAPIFiles: Codable {
  let mp4 : StreamableAPIFile?
  let mp4Mobile:  StreamableAPIFile?

  enum CodingKeys : String, CodingKey {
    case mp4 = "mp4"
    case mp4Mobile = "mp4-mobile"
  }
}

struct StreamableAPIFile: Codable {
  let url: String
  let width: Int
  let height: Int
}
