import NukeUI
import SwiftUI

struct LightBoxElementView: View {
  var el: ImgExtracted
  var width: CGFloat
  var label: String?
  var onTap: (() -> Void)?
  var onSwipe: ((Int) -> Void)?
  var onHold: ((LightBoxScrub) -> Void)?
  var doLiveText: Bool
  var showOverlay: Bool
  var gifScrubber: GIFScrubber?
  @Binding var isPinching: Bool
  @State private var altSize: CGSize = .zero
  @Binding var isZoomed: Bool
  var body: some View {
    ZoomableScrollView(onTap: onTap, onSwipe: onSwipe, onHold: onHold, isZoomed: $isZoomed) {
      URLImage(url: el.url, doLiveText: doLiveText, showOverlay: showOverlay, gifScrubber: gifScrubber)
        .scaledToFit()
    }
    .modifier(LightBoxImageAccessibility(label: label ?? "Image", keepsLiveText: doLiveText))
    .id("\(el.id)\(altSize.width + altSize.height)")
    .frame(width: width)
    .preferredColorScheme(.dark)
    .edgesIgnoringSafeArea(.all)
    .statusBar(hidden: true)
  }
}

private struct LightBoxImageAccessibility: ViewModifier {
  var label: String
  var keepsLiveText: Bool

  func body(content: Content) -> some View {
    if keepsLiveText {
      content
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    } else {
      content
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isImage)
    }
  }
}
