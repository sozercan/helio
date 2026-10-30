//
//  PreviewModel.swift
//  Helio
//
//  Created by Igor Marcossi on 26/09/23.
//

import Defaults
import Foundation
import NukeUI
import OpenGraph
import SwiftUI

@Observable
final class PreviewModel: Equatable {
  static func == (lhs: PreviewModel, rhs: PreviewModel) -> Bool {
    lhs.url == rhs.url
  }

  var imageReq: ImageRequest?
  var title: String?
  var url: URL?
  var description: String?
  var loading = true

  var previewURL: URL?

  init() {}

  init(_ url: URL, compact: Bool) {
    self.previewURL = url
    Task {
      await fetchMetadata(compact: compact)
    }
  }

  private func fetchMetadata(compact: Bool) async {
    guard let previewURL else { return }

    var headers = [String: String]()
    headers["User-Agent"] = "facebookexternalhit/1.1"
    headers["charset"] = "UTF-8"
    if let og = try? await OpenGraph.fetch(url: previewURL, headers: headers) {
      var newImageReq: ImageRequest?
      if let imgURL = URL(string: og[.image] ?? "") {
        newImageReq = ImageRequest(url: imgURL, processors: [.resize(width: compact ? scaledCompactModeThumbSize() : 76)])
      }
      // Not animated: this usually lands while the feed is scrolling, where an animated
      // commit causes a hitch.
      await MainActor.run { [newImageReq] in
        imageReq = newImageReq
        title = og[.title]?.escape
        description = og[.description]?.escape
        url = URL(string: og[.url] ?? "")
        loading = false
      }
    } else {
      await MainActor.run {
        loading = false
      }
    }
  }
}
