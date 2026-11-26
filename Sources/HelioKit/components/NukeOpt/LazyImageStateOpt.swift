import Combine
import Foundation
import Nuke
import NukeUI
import SwiftUI

@MainActor
public protocol LazyImageStateOpt {
  var result: Result<ImageResponse, Error>? { get }

  var imageContainer: ImageContainer? { get }
}

public extension LazyImageStateOpt {
  var error: Error? {
    if case let .failure(error) = result {
      return error
    }
    return nil
  }

  var image: Image? {
    #if os(macOS)
      imageContainer.map { Image(nsImage: $0.image) }
    #else
      imageContainer.map { Image(uiImage: $0.image) }
    #endif
  }
}
