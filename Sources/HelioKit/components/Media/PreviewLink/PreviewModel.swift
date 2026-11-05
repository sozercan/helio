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
import Synchronization

@Observable
final class PreviewModel: Equatable {
  /// The same model, not just the same link: a refresh makes a new one, which a layout cached
  /// with the old one (`Post.pageLayout`) has to pick up, as the old one may have failed to load.
  static func == (lhs: PreviewModel, rhs: PreviewModel) -> Bool {
    lhs === rhs
  }

  var imageReq: ImageRequest?
  var title: String?
  var url: URL?
  var description: String?
  var loading = true

  var previewURL: URL?
  /// The key this model is shared under, when it is.
  @ObservationIgnored private var sharedKey: NSString?

  private static let instances: NSCache<NSString, PreviewModel> = {
    let cache = NSCache<NSString, PreviewModel>()
    cache.countLimit = 300
    return cache
  }()

  /// The model for a link in a layout. A post is laid out compact and full, laid out again when
  /// the window resizes, and views rebuild their previews on every update; they all share one
  /// model instead of each downloading the page. A model whose download failed is dropped, so a
  /// later layout tries again (`LinkMetadataLoader` waits a while between attempts).
  /// Without `fetch`, the page is downloaded only once the preview shows (`loadIfNeeded()`), for
  /// layouts that don't show previews, such as the canvas.
  static func shared(_ url: URL, compact: Bool, fetch: Bool = true) -> PreviewModel {
    let key = "\(compact ? "c" : "n")|\(url.absoluteString)" as NSString
    if let model = instances.object(forKey: key) {
      if fetch {
        model.loadIfNeeded()
      }
      return model
    }
    let model = PreviewModel(url, compact: compact, sharedKey: key, fetch: fetch)
    instances.setObject(model, forKey: key)
    return model
  }

  init() {
    self.compact = false
  }

  init(_ url: URL, compact: Bool, sharedKey: NSString? = nil, fetch: Bool = true) {
    self.previewURL = url
    self.sharedKey = sharedKey
    self.compact = compact
    if fetch {
      loadIfNeeded()
    }
  }

  private let compact: Bool
  /// Layouts are built off the main thread, several at once.
  private let started = Mutex(false)

  /// Whether the page's metadata has been asked for.
  var hasStartedLoading: Bool {
    started.withLock { $0 }
  }

  /// Downloads the page's metadata, once.
  func loadIfNeeded() {
    let first = started.withLock { started in
      defer { started = true }
      return !started
    }
    guard first else { return }
    Task(priority: .utility) {
      await fetchMetadata(compact: compact)
    }
  }

  private func fetchMetadata(compact: Bool) async {
    guard let previewURL else { return }

    if let og = await LinkMetadataLoader.shared.metadata(for: previewURL) {
      var newImageReq: ImageRequest?
      if let imgURL = URL(string: og.image ?? "") {
        newImageReq = ImageRequest(url: imgURL, processors: [.resize(width: compact ? scaledCompactModeThumbSize() : 76)])
      }
      // Not animated: this usually lands while the feed is scrolling, where an animated
      // commit causes a hitch.
      await MainActor.run { [newImageReq] in
        imageReq = newImageReq
        title = og.title?.escape
        description = og.description?.escape
        url = URL(string: og.url ?? "")
        loading = false
      }
    } else {
      if let sharedKey, Self.instances.object(forKey: sharedKey) === self {
        Self.instances.removeObject(forKey: sharedKey)
      }
      await MainActor.run {
        loading = false
      }
    }
  }
}

/// Open Graph metadata of web pages, one download per page however many previews show it.
actor LinkMetadataLoader {
  static let shared = LinkMetadataLoader()

  /// A page that failed to load is tried again after this long.
  static let failureRetryInterval: TimeInterval = 120

  struct Metadata: Sendable {
    let title: String?
    let description: String?
    let image: String?
    let url: String?
  }

  private let fetch: @Sendable (URL) async -> Metadata?
  private var loaded: [URL: Metadata] = [:]
  private var failed: [URL: Date] = [:]
  private var inFlight: [URL: Task<Metadata?, Never>] = [:]

  init(fetch: @escaping @Sendable (URL) async -> Metadata? = { url in
    let headers = ["User-Agent": "facebookexternalhit/1.1", "charset": "UTF-8"]
    guard let og = try? await OpenGraph.fetch(url: url, headers: headers) else { return nil }
    return Metadata(title: og[.title], description: og[.description], image: og[.image], url: og[.url])
  }) {
    self.fetch = fetch
  }

  func metadata(for url: URL) async -> Metadata? {
    if let metadata = loaded[url] {
      return metadata
    }
    if let failedAt = failed[url], Date().timeIntervalSince(failedAt) < Self.failureRetryInterval {
      return nil
    }
    if let task = inFlight[url] {
      return await task.value
    }
    let task = Task { [fetch] in await fetch(url) }
    inFlight[url] = task
    let metadata = await task.value
    inFlight[url] = nil
    if let metadata {
      loaded[url] = metadata
      failed[url] = nil
    } else {
      failed[url] = Date()
    }
    return metadata
  }
}
