//
//  GIFViewer.swift
//  Helio
//
//  Created by Igor Marcossi on 29/10/23.
//

import Gifu
import Nuke
import NukeUI
import SwiftUI

/// An image view for displaying animated images.
public struct GIFImage: UIViewRepresentable {
  private enum Source {
    case data(Data)
    case url(URL)
    case imageName(String)
  }

  private let source: Source
  private var loopCount = 0
  private var size: CGSize = .zero

  /// Initializes the view with the given GIF image data.
  public init(data: Data, size: CGSize? = nil) {
    self.source = .data(data)
    if let size {
      self.size = size
    }
  }

  public func makeUIView(context: Context) -> GIFImageView {
    let view = GIFImageView(frame: .init(origin: .zero, size: self.size))
    view.contentMode = .scaleAspectFill
    view.frame.size = self.size
    view.clipsToBounds = true
    view.translatesAutoresizingMaskIntoConstraints = false
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.setContentHuggingPriority(.required, for: .horizontal)
    view.setContentHuggingPriority(.required, for: .vertical)
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    return view
  }

  public func updateUIView(_ view: GIFImageView, context: Context) {
    switch source {
    case let .data(data):
      view.animate(withGIFData: data, loopCount: loopCount)
    case let .url(url):
      view.animate(withGIFURL: url, loopCount: loopCount)
    case let .imageName(imageName):
      view.animate(withGIFNamed: imageName, loopCount: loopCount)
    }
    view.contentMode = .scaleAspectFill
    view.clipsToBounds = true
    view.frame.size = self.size
    view.translatesAutoresizingMaskIntoConstraints = false
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.setContentHuggingPriority(.required, for: .horizontal)
    view.setContentHuggingPriority(.required, for: .vertical)
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
  }

  public static func dismantleUIView(
    _ uiView: GIFImageView,
    coordinator: Coordinator,
  ) {
    uiView.prepareForReuse()
  }
}

class LoadingImgView: UIImageView {
  init() {
    let loadingImg = UIImage(named: "loader")
    super.init(image: loadingImg)
    self.frame = .init(origin: .zero, size: CGSize(width: 75, height: 75))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
