import Foundation
import SwiftUI
import YouTubePlayerKit

struct PreviewLink: View {
  var url: URL
  var compact = false
  @State var previewModel: PreviewModel

  var body: some View {
    PreviewLinkContent(compact: compact, viewModel: previewModel, url: url)
  }
}
