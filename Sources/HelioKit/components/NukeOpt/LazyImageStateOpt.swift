//
//  LazyImageStateOpt.swift
//  Helio
//
//  Created by Igor Marcossi on 14/04/24.
//
import Combine
import Foundation
import Nuke
import NukeUI
import SwiftUI

/// Describes current image state.
@MainActor
public protocol LazyImageStateOpt {
  /// Returns the current fetch result.
  var result: Result<ImageResponse, Error>? { get }

  /// Returns the fetched image.
  ///
  /// - note: In case pipeline has `isProgressiveDecodingEnabled` option enabled
  /// and the image being downloaded supports progressive decoding, the `image`
  /// might be updated multiple times during the download.
  var imageContainer: ImageContainer? { get }
}

public extension LazyImageStateOpt {
  /// Returns the current error.
  var error: Error? {
    if case let .failure(error) = result {
      return error
    }
    return nil
  }

  /// Returns an image view.
  var image: Image? {
    #if os(macOS)
      imageContainer.map { Image(nsImage: $0.image) }
    #else
      imageContainer.map { Image(uiImage: $0.image) }
    #endif
  }
}
