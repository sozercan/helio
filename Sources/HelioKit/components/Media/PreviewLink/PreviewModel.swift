import Defaults
import Foundation
import NukeUI
import OpenGraph
import SwiftUI
import Synchronization

@Observable
final class PreviewModel: Equatable {
  static func == (lhs: PreviewModel, rhs: PreviewModel) -> Bool {
    lhs === rhs
  }

  var imageReq: ImageRequest?
  var title: String?
  var url: URL?
  var description: String?
  var loading = true

  var previewURL: URL?
  @ObservationIgnored private var sharedKey: NSString?

  private static let instances: NSCache<NSString, PreviewModel> = {
    let cache = NSCache<NSString, PreviewModel>()
    cache.countLimit = 300
    return cache
  }()

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
  private let started = Mutex(false)

  var hasStartedLoading: Bool {
    started.withLock { $0 }
  }

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

actor LinkMetadataLoader {
  static let shared = LinkMetadataLoader()

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
