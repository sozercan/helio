import Defaults
import NukeUI
import SwiftUI

enum LightBoxMedia {
  case image(ImgExtracted)
  case video(SharedVideo, holder: VideoPlayerHolder? = nil)

  var image: ImgExtracted? {
    if case let .image(img) = self {
      img
    } else {
      nil
    }
  }

  var isScrubbable: Bool {
    switch self {
    case let .image(img): img.url.isGIF
    case .video: true
    }
  }

  static func of(_ media: MediaExtractedType?) -> [LightBoxMedia] {
    switch media {
    case let .imgs(images): images.map { .image($0) }
    case let .video(video): [.video(video)]
    default: []
    }
  }
}

struct LightBoxPost {
  var key: String
  var title: String?
  var badgeKit: BadgeKit?
  var avatarImageRequest: ImageRequest?
  var markAsSeen: (() async -> Void)?
  var feedID: String?

  func pages(_ media: [LightBoxMedia]) -> [LightBoxPage] {
    media.enumerated().map { LightBoxPage(media: $1, post: self, index: $0, count: media.count) }
  }

  func pages(_ images: [ImgExtracted]) -> [LightBoxPage] {
    pages(images.map { .image($0) })
  }
}

struct LightBoxPage {
  var media: LightBoxMedia
  var post: LightBoxPost
  var index: Int
  var count: Int
}

struct LightBoxTimeline: Identifiable {
  let id = UUID()
  var pages: [LightBoxPage]
  var start: Int
  var reveal: ((String) -> Void)?

  @MainActor
  static func around(_ helioData: PostHelioData?, in feed: (any FeedPostsSource)?, own: [LightBoxPage], start: Int) -> LightBoxTimeline {
    guard let helioData, let posts = feed?.feedPosts, posts.contains(where: { $0.helioData === helioData }) else {
      return LightBoxTimeline(pages: own, start: start)
    }
    let settings = CachedDefaults[.PostLinkDefSettings]
    var pages: [LightBoxPage] = []
    var startPage = start
    for post in posts {
      if post.helioData === helioData {
        startPage = pages.count + start
        pages += own.map {
          var page = $0
          page.post.feedID = post.id
          return page
        }
        continue
      }
      guard let data = post.data, let postHelioData = post.helioData else { continue }
      let media = LightBoxMedia.of(postHelioData.extractedMedia)
      guard !media.isEmpty else { continue }
      if settings.blurNSFW, data.over_18 ?? false {
        continue
      }
      let markAsSeen: (() async -> Void)? = settings.lightboxReadsPost ? { await post.toggleSeen(true) } : nil
      pages += LightBoxPost(key: post.id, title: data.title, badgeKit: data.badgeKit, avatarImageRequest: postHelioData.avatarImageRequest, markAsSeen: markAsSeen, feedID: post.id).pages(media)
    }
    return LightBoxTimeline(pages: pages, start: startPage) { [weak feed] in feed?.reveal($0) }
  }
}

struct FeedRevealRequest: Equatable {
  let postID: String
  let token = UUID()
}

@MainActor
protocol FeedPostsSource: AnyObject {
  var feedPosts: [Post] { get }
  func reveal(_ postID: String)
}

extension FeedItemsManager: FeedPostsSource {
  var feedPosts: [Post] {
    entities.compactMap {
      if case let .post(post) = $0 {
        post
      } else {
        nil
      }
    }
  }

  func reveal(_ postID: String) {
    revealRequest = FeedRevealRequest(postID: postID)
  }
}

extension EnvironmentValues {
  @Entry var feedPostsSource: (any FeedPostsSource)?
}

@MainActor @Observable
final class LightBoxPresenter {
  var timeline: LightBoxTimeline?

  func isShowing(_ holder: VideoPlayerHolder) -> Bool {
    timeline?.pages.contains {
      if case let .video(_, borrowed) = $0.media {
        borrowed === holder
      } else {
        false
      }
    } ?? false
  }
}

extension EnvironmentValues {
  @Entry var lightBoxPresenter: LightBoxPresenter?
}

private struct LightBoxPresenting: ViewModifier {
  @State private var presenter = LightBoxPresenter()

  func body(content: Content) -> some View {
    content
      .environment(\.lightBoxPresenter, presenter)
      .fullScreenCover(item: $presenter.timeline) { timeline in
        LightBoxImage(pages: timeline.pages, i: timeline.start, doLiveText: Defaults[.BehaviorDefSettings].doLiveText, reveal: timeline.reveal)
      }
  }
}

extension View {
  func lightBoxPresenting() -> some View {
    modifier(LightBoxPresenting())
  }
}
