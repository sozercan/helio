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
        let configsArray: ImageAnalyzer.AnalysisTypes = [.text, .machineReadableCode]
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
  override var intrinsicContentSize: CGSize {
    window?.bounds.size ?? CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    invalidateIntrinsicContentSize()
  }
}
