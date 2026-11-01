//
//  ImageSize.swift
//  Helio
//
//  Created by Igor Marcossi on 30/12/23.
//

import SwiftUI

extension Image {
  func size(_ size: Double, _ contentMode: ContentMode = .fit) -> some View {
    self.resizable().aspectRatio(contentMode: contentMode).frame(size)
  }
}
