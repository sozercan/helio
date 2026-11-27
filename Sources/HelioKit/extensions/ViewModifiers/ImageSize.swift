import SwiftUI

extension Image {
  func size(_ size: Double, _ contentMode: ContentMode = .fit) -> some View {
    self.resizable().aspectRatio(contentMode: contentMode).frame(size)
  }
}
