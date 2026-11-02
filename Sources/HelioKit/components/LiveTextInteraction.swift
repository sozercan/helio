//
//  LiveTextInteraction.swift
//  Helio
//
//  Created by Daniel Inama on 25/08/23.
//

import SwiftUI
import UIKit
import VisionKit

@MainActor
struct LiveTextInteraction: UIViewRepresentable {
  var image: Image
  var showOverlay: Bool
  let analyzer = ImageAnalyzer()
  let interaction = ImageAnalysisInteraction()

  func makeUIView(context: Context) -> some UIView {
    let imageView = LiveTextImageView()
    guard let image = ImageRenderer(content: image).uiImage else {
      imageView.image = UIImage(named: "emptyThumb")
      return imageView
    }
    imageView.image = image
    if ImageAnalyzer.isSupported {
      imageView.addInteraction(interaction)
    }
    imageView.contentMode = .scaleAspectFit

    Task {
      if ImageAnalyzer.isSupported {
        let configsArray: ImageAnalyzer.AnalysisTypes = [.text, .machineReadableCode] // .visualLookup crashes iOS 16.X devices even if you check for it in an if
        let configuration = ImageAnalyzer.Configuration(configsArray)
        do {
          let analysis = try await analyzer.analyze(image, configuration: configuration)
          interaction.preferredInteractionTypes = .automatic
          interaction.isSupplementaryInterfaceHidden = false
          interaction.analysis = analysis
        } catch {
          print(error)
        }
      }
    }

    return imageView
  }

  func updateUIView(_ uiView: UIViewType, context: Context) {
    if let view = uiView as? LiveTextImageView,
       let interaction = uiView.interactions.first as? ImageAnalysisInteraction,
       showOverlay == interaction.isSupplementaryInterfaceHidden
    {
      interaction.setSupplementaryInterfaceHidden(!showOverlay, animated: true)
    }
  }
}

class LiveTextImageView: UIImageView {
  /// The window's size rather than the image's, so SwiftUI sizes the view by its frame. Not the
  /// screen's: the window can be smaller (iPad multitasking, a Mac window, the folded iPhone Duo).
  override var intrinsicContentSize: CGSize {
    window?.bounds.size ?? CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    invalidateIntrinsicContentSize()
  }
}
