import Defaults
import Nuke
import NukeUI
import SwiftUI

struct ImageMediaPostCompactMoreImagesOverlay: View, Equatable {
  var count: Int
  var body: some View {
    Text("\(count)+")
      .fontSize(12, .semibold)
      .padding(.all, 6)
      .background(Circle().fill(.bar))
      .padding(.all, 4)
      .allowsHitTesting(false)
  }
}

struct ImageMediaPost: View, Equatable {
  static let gallerySpacing: CGFloat = 8
  static func == (lhs: ImageMediaPost, rhs: ImageMediaPost) -> Bool {
    lhs.postTitle == rhs.postTitle && lhs.compact == rhs.compact && lhs.contentWidth == rhs.contentWidth && lhs.badgeKit == rhs.badgeKit && lhs.cornerRadius == rhs.cornerRadius
  }

  var fullPage = false
  let postTitle: String
  let badgeKit: BadgeKit
  let avatarImageRequest: ImageRequest?
  let markAsSeen: (() async -> Void)?
  var cornerRadius: Double
  var compact = false
  var images: [ImgExtracted]
  var contentWidth: CGFloat
  var maxMediaHeightScreenPercentage: CGFloat
  var feedPost: PostHelioData?
  @Environment(\.feedPostsSource) private var feed
  @Environment(\.lightBoxPresenter) private var presenter
  @State private var lightbox: LightBoxTimeline?

  private func open(_ index: Int) {
    let own = LightBoxPost(key: "opened", title: postTitle, badgeKit: badgeKit, avatarImageRequest: avatarImageRequest, markAsSeen: markAsSeen).pages(images)
    let timeline = LightBoxTimeline.around(feedPost, in: feed, own: own, start: index)
    if let presenter {
      presenter.timeline = timeline
    } else {
      withAnimation(spring) { lightbox = timeline }
    }
  }

  var body: some View {
    let maxHeight: CGFloat = (maxMediaHeightScreenPercentage / 100) * .screenH
    VStack {
      if images.count == 1 || compact && !images.isEmpty {
        let img = images[0]
        let knownSize = img.size.width > 0 && img.size.height > 0
        let sourceHeight = knownSize ? img.size.height : contentWidth
        let sourceWidth = knownSize ? img.size.width : contentWidth

        let propHeight = (contentWidth * sourceHeight) / sourceWidth
        let finalHeight = maxMediaHeightScreenPercentage != 110 ? Double(min(maxHeight, propHeight)) : Double(propHeight)

        let capped = !compact && knownSize && finalHeight < propHeight - 1
        let thumbWidth = compact ? scaledCompactModeThumbSize() : capped ? (finalHeight * sourceWidth) / sourceHeight : contentWidth
        GalleryThumb(cornerRadius: capped ? 0 : cornerRadius, width: thumbWidth, height: compact ? scaledCompactModeThumbSize() : finalHeight, url: img.url, imgRequest: !images.isEmpty ? images[0].request : nil, posterURL: img.posterURL)
          .equatable()
          .frame(width: capped ? contentWidth : nil)
          .background(capped ? Color.primary.opacity(0.06) : .clear)
          .mask(RR(capped ? cornerRadius : 0, Color.black))
          .onTapGesture { open(0) }
          .mediaImageAccessibility(postTitle, index: 0, count: images.count)
          .overlay(
            !compact || images.count <= 1
              ? nil
              : ImageMediaPostCompactMoreImagesOverlay(count: images.count - 1).equatable(),
            alignment: .bottomTrailing,
          )

      } else if images.count > 1 {
        let width = ((contentWidth - 8) / 2)
        let height = width
        VStack(spacing: ImageMediaPost.gallerySpacing) {
          HStack(spacing: ImageMediaPost.gallerySpacing) {
            GalleryThumb(cornerRadius: cornerRadius, width: compact ? scaledCompactModeThumbSize() : width, height: compact ? scaledCompactModeThumbSize() : height, url: images[0].url, imgRequest: !images.isEmpty ? images[0].request : nil)
              .equatable()
              .onTapGesture { open(0) }
              .mediaImageAccessibility(postTitle, index: 0, count: images.count)

            GalleryThumb(cornerRadius: cornerRadius, width: width, height: height, url: images[1].url, imgRequest: images.count > 1 ? images[1].request : nil)
              .equatable()
              .onTapGesture { open(1) }
              .mediaImageAccessibility(postTitle, index: 1, count: images.count)
          }

          if images.count > 2 {
            HStack(spacing: ImageMediaPost.gallerySpacing) {
              GalleryThumb(cornerRadius: cornerRadius, width: images.count == 3 ? contentWidth : width, height: height, url: images[2].url, imgRequest: images.count > 2 ? images[2].request : nil)
                .equatable()
                .onTapGesture { open(2) }
                .mediaImageAccessibility(postTitle, index: 2, count: images.count)
              if images.count == 4 {
                GalleryThumb(cornerRadius: cornerRadius, width: width, height: height, url: images[3].url, imgRequest: images.count > 3 ? images[3].request : nil)
                  .equatable()
                  .onTapGesture { open(3) }
                  .mediaImageAccessibility(postTitle, index: 3, count: images.count)
              } else if images.count > 4 {
                Text("\(images.count - 3)+")
                  .fontSize(24, .medium)
                  .frame(width: width - 56, height: height - 56)
                  .background(Circle().fill(.primary.opacity(0.05)))
                  .frame(width: width, height: height)
                  .onTapGesture { open(0) }
                  .accessibilityLabel("\(images.count - 3) more images")
              }
            }
          }
        }
      }
    }
    .frame(maxWidth: compact ? nil : .infinity)
    .fullScreenCover(item: $lightbox) { lightbox in
      LightBoxImage(pages: lightbox.pages, i: lightbox.start, doLiveText: Defaults[.BehaviorDefSettings].doLiveText, reveal: lightbox.reveal)
    }
  }
}

extension View {
  func mediaImageAccessibility(_ title: String, index: Int, count: Int) -> some View {
    accessibilityElement(children: .ignore)
      .accessibilityLabel(count > 1 ? "\(title), image \(index + 1) of \(count)" : title)
      .accessibilityAddTraits(.isImage)
  }
}

func scaledCompactModeThumbSize(compact: Bool = CachedDefaults[.PostLinkDefSettings].compactMode.enabled, thumbnailSize: ThumbnailSizeModifier = CachedDefaults[.PostLinkDefSettings].compactMode.thumbnailSize) -> CGFloat {
  if compact {
    compactModeThumbSize * thumbnailSize.rawVal
  } else {
    compactModeThumbSize
  }
}

extension Int: Identifiable {
  public var id: Int {
    self
  }
}
