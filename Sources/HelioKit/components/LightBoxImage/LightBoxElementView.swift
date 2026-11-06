//
//  LightBoxElementView.swift
//  Helio
//
//  Created by Igor Marcossi on 07/08/23.
//

import NukeUI
import SwiftUI

struct LightBoxElementView: View {
  var el: ImgExtracted
  /// The post's title, VoiceOver's label for the image.
  var label: String?
  var onTap: (() -> Void)?
  var doLiveText: Bool
  var showOverlay: Bool
  /// Set when a sideways swipe scrubs this GIF.
  var gifScrubber: GIFScrubber?
  @Binding var isPinching: Bool
  @State private var altSize: CGSize = .zero
  @Binding var isZoomed: Bool
  var body: some View {
    ZoomableScrollView(onTap: onTap, isZoomed: $isZoomed) {
      URLImage(url: el.url, doLiveText: doLiveText, showOverlay: showOverlay, gifScrubber: gifScrubber)
        .scaledToFit()
    }
    .modifier(LightBoxImageAccessibility(label: label ?? "Image", keepsLiveText: doLiveText))
    .id("\(el.id)\(altSize.width + altSize.height)")
    .frame(width: .screenW)
    .preferredColorScheme(.dark)
    .edgesIgnoringSafeArea(.all)
    .statusBar(hidden: true)
  }
}

/// One labeled image for VoiceOver. With Live Text on, the image's recognized text and codes stay
/// reachable inside it instead of being folded into the label.
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
