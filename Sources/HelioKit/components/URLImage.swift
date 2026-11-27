import Nuke
import NukeExtensions
import NukeUI
import SwiftUI
import VisionKit

struct URLImage: View, Equatable {
  static func == (lhs: URLImage, rhs: URLImage) -> Bool {
    lhs.url == rhs.url && lhs.imgRequest?.url == rhs.imgRequest?.url && lhs.showOverlay == rhs.showOverlay && lhs.gifScrubber === rhs.gifScrubber
  }

  let url: URL
  var doLiveText: Bool = false
  var showOverlay: Bool = false
  var imgRequest: ImageRequest?
  var processors: [ImageProcessing]?
  var size: CGSize?
  var posterURL: URL?
  var gifScrubber: GIFScrubber?

  var body: some View {
    image.accessibilityIgnoresInvertColors()
  }

  @ViewBuilder
  private var image: some View {
    if url.isGIF {
      LazyImageOpt(url: url) { state in
        if let imageData = state.imageContainer?.data {
          if let gifScrubber {
            ScrubbableGIF(data: imageData, scrubber: gifScrubber)
              .scaledToFit()
              .frame(width: size?.width, height: size?.height)
          } else {
            GIFImage(data: imageData, size: size)
              .scaledToFit()
              .frame(width: size?.width, height: size?.height)
          }
        } else if state.error != nil {
          Color.red.opacity(0.1)
            .overlay(Image(systemName: "xmark.circle.fill").foregroundColor(.red))
        } else {
          ZStack {
            if let posterURL {
              LazyImageOpt(url: posterURL) { posterState in
                posterState.image?
                  .resizable()
                  .scaledToFill()
              }
            }
            URLImageLoader(size: 50).scaledToFit()
          }
        }
      }
      .onDisappear(.cancel)
      .processors(processors)
    } else {
      if let imgRequest {
        LazyImageOpt(request: imgRequest, transaction: .init(animation: .default)) { state in
          if let image = state.image {
            if doLiveText, ImageAnalyzer.isSupported {
              LiveTextInteraction(image: image, showOverlay: showOverlay)
                .scaledToFill()
                .frame(width: size?.width, height: size?.height)
            } else {
              image
                .resizable()
                .scaledToFill()
                .frame(width: size?.width, height: size?.height)
            }
          }
        }
        .onDisappear(.cancel)
      } else {
        LazyImageOpt(url: url) { state in
          if let image = state.image {
            if doLiveText, ImageAnalyzer.isSupported {
              LiveTextInteraction(image: image, showOverlay: showOverlay)

                .frame(width: size?.width, height: size?.height)
                .scaledToFit()
            } else {
              image
                .resizable()
                .frame(width: size?.width, height: size?.height)
                .scaledToFit()
            }
          } else if state.error != nil {
            Color.red.opacity(0.1)
              .overlay(Image(systemName: "xmark.circle.fill").foregroundColor(.red))
          } else {
            URLImageLoader(size: 50).scaledToFit()
          }
        }
        .onDisappear(.cancel)
        .processors(processors)
      }
    }
  }
}

struct ThumbReqImage: View, Equatable {
  static func == (lhs: ThumbReqImage, rhs: ThumbReqImage) -> Bool {
    lhs.imgRequest.url == rhs.imgRequest.url
  }

  var imgRequest: ImageRequest

  var body: some View {
    image.accessibilityIgnoresInvertColors()
  }

  private var image: some View {
    LazyImageOpt(request: imgRequest, transaction: .init(animation: .default)) { state in
      if let image = state.image {
        image
      } else {
        Color.acceptablePrimary.opacity(0.3)
      }
    }
    .onDisappear(.cancel)
  }
}

struct URLImageLoader: View, Equatable {
  let size: Double

  var body: some View {
    Image(.loader)
      .resizable()
      .scaledToFit()
      .mask(Circle())
      .opacity(0.5)
      .frame(maxWidth: size, maxHeight: size)
  }
}
