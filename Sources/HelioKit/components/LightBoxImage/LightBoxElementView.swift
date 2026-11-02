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
  @Binding var isPinching: Bool
  @State private var altSize: CGSize = .zero
  @Binding var isZoomed: Bool
  var body: some View {
    ZoomableScrollView(onTap: onTap, isZoomed: $isZoomed) {
      URLImage(url: el.url, doLiveText: doLiveText, showOverlay: showOverlay)
        .scaledToFit()
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label ?? "Image")
    .accessibilityAddTraits(.isImage)
    .id("\(el.id)\(altSize.width + altSize.height)")
    .frame(width: .screenW)
    .preferredColorScheme(.dark)
    .edgesIgnoringSafeArea(.all)
    .statusBar(hidden: true)
  }
}
