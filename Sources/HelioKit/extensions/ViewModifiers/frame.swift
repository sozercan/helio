import Foundation
import SwiftUI

extension View {
  func frame(_ size: CGFloat?, _ alignment: Alignment = .center) -> some View {
    self.frame(width: size, height: size, alignment: alignment)
  }

  func frame(_ size: CGSize?, _ alignment: Alignment = .center) -> some View {
    self.frame(width: size?.width, height: size?.height, alignment: alignment)
  }
}
