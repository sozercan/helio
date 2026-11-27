import AVFoundation
import Foundation
import os
import UniformTypeIdentifiers

enum RedditVideoPlaylistRecovery {
  private static let logger = Logger(subsystem: "com.sertacozercan.helio", category: "Video")
  static let customScheme = "helio-hls"

  enum RecoveredSource: Equatable, Sendable {
    case manifest(String, sourceURL: URL)
    case directURL(URL)
  }

  static func isRedditHLSPlaylist(_ url: URL) -> Bool {
    guard let host = url.host?.lowercased(), host == "v.redd.it" else { return false }
    return url.lastPathComponent.lowercased() == "hlsplaylist.m3u8"
  }

  static func dashURL(for hlsURL: URL) -> URL? {
    guard isRedditHLSPlaylist(hlsURL) else { return nil }
    return hlsURL.deletingLastPathComponent().appendingPathComponent("DASHPlaylist.mpd")
  }

  static func customSchemeURL(for hlsURL: URL) -> URL? {
    guard var components = URLComponents(url: hlsURL, resolvingAgainstBaseURL: false) else { return nil }
    components.scheme = customScheme
    return components.url
  }

  static func makePlayerItem(for source: RecoveredSource) -> (item: AVPlayerItem, delegate: AVAssetResourceLoaderDelegate?) {
    switch source {
    case let .manifest(manifest, sourceURL):
      guard let schemeURL = customSchemeURL(for: sourceURL) else {
        return (AVPlayerItem(url: sourceURL), nil)
      }
      let asset = AVURLAsset(url: schemeURL)
      let delegate = PlaylistResourceLoader(manifest: manifest)
      asset.resourceLoader.setDelegate(delegate, queue: delegate.queue)
      return (AVPlayerItem(asset: asset), delegate)
    case let .directURL(url):
      return (AVPlayerItem(url: url), nil)
    }
  }

  static func recover(
    hlsURL: URL,
    dashURL: URL?,
    fallbackURL: URL?,
    fetch: (URL) async throws -> Data = fetchData,
  ) async -> RecoveredSource? {
    guard isRedditHLSPlaylist(hlsURL) else {
      return fallbackURL.map(RecoveredSource.directURL)
    }
    let baseURL = hlsURL.deletingLastPathComponent()
    let candidates = [dashURL, Self.dashURL(for: hlsURL)].compactMap(\.self)
    var tried: Set<URL> = []
    for candidate in candidates where tried.insert(candidate).inserted {
      do {
        let data = try await fetch(candidate)
        if let manifest = buildMultivariantPlaylist(fromDASHData: data, baseURL: baseURL) {
          return .manifest(manifest, sourceURL: hlsURL)
        }
      } catch {
        logger.debug("DASH playlist recovery fetch failed for \(candidate.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
      }
    }
    return fallbackURL.map(RecoveredSource.directURL)
  }

  static func buildMultivariantPlaylist(fromDASHData data: Data, baseURL: URL) -> String? {
    let parser = DASHParser()
    guard let parsed = parser.parse(data), !parsed.videos.isEmpty else { return nil }

    var lines = ["#EXTM3U", "#EXT-X-VERSION:4"]
    let audioGroupID = "audio"
    let hasAudio = !parsed.audios.isEmpty

    let sortedAudios = parsed.audios.sorted { ($0.bandwidth ?? 0) > ($1.bandwidth ?? 0) }
    for (index, audio) in sortedAudios.enumerated() {
      guard let playlistURI = variantPlaylistURL(from: audio.baseURL, baseURL: baseURL) else { continue }
      let isDefault = index == 0 ? "YES" : "NO"
      let name = audio.bandwidth.map { "audio \($0 / 1000)k" } ?? "audio \(index)"
      lines.append(
        "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"\(audioGroupID)\",NAME=\"\(name)\",DEFAULT=\(isDefault),AUTOSELECT=\(isDefault),URI=\"\(playlistURI.absoluteString)\"",
      )
    }

    let audioCodec = sortedAudios.first?.codecs
    let audioBandwidth = sortedAudios.first?.bandwidth ?? 0
    var addedVideo = false

    for video in parsed.videos {
      guard let playlistURI = variantPlaylistURL(from: video.baseURL, baseURL: baseURL) else { continue }
      let bandwidth = max(1, (video.bandwidth ?? 0) + (hasAudio ? audioBandwidth : 0))
      var attributes = ["BANDWIDTH=\(bandwidth)"]
      if let width = video.width, let height = video.height, width > 0, height > 0 {
        attributes.append("RESOLUTION=\(width)x\(height)")
      }
      if let frameRate = video.frameRate, !frameRate.isEmpty {
        attributes.append("FRAME-RATE=\(frameRate)")
      }
      let codecs = [video.codecs, hasAudio ? audioCodec : nil].compactMap(\.self).filter { !$0.isEmpty }
      if !codecs.isEmpty {
        attributes.append("CODECS=\"\(codecs.joined(separator: ","))\"")
      }
      if hasAudio {
        attributes.append("AUDIO=\"\(audioGroupID)\"")
      }
      lines.append("#EXT-X-STREAM-INF:\(attributes.joined(separator: ","))")
      lines.append(playlistURI.absoluteString)
      addedVideo = true
    }

    guard addedVideo else { return nil }
    return lines.joined(separator: "\n") + "\n"
  }

  static func variantPlaylistURL(from dashBaseURL: String, baseURL: URL) -> URL? {
    let trimmed = dashBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let fileURL = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
    guard let fileURL else { return nil }
    let filename = fileURL.lastPathComponent
    guard filename.lowercased().hasSuffix(".mp4") else { return nil }
    let stem = String(filename.dropLast(4))
    guard !stem.isEmpty else { return nil }
    return fileURL.deletingLastPathComponent().appendingPathComponent("\(stem).m3u8")
  }

  private static func fetchData(_ url: URL) async throws -> Data {
    var request = URLRequest(url: url)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.timeoutInterval = 10
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
      throw URLError(.badServerResponse)
    }
    return data
  }

  final class PlaylistResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    private let manifestData: Data
    // swiftlint:disable:next no_dispatch_queue
    let queue = DispatchQueue(label: "com.sertacozercan.helio.hls-recovery")

    init(manifest: String) {
      self.manifestData = Data(manifest.utf8)
    }

    func resourceLoader(_: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
      guard loadingRequest.request.url?.scheme?.lowercased() == RedditVideoPlaylistRecovery.customScheme else {
        return false
      }
      if let contentInfo = loadingRequest.contentInformationRequest {
        contentInfo.contentType = UTType.m3uPlaylist.identifier
        contentInfo.contentLength = Int64(manifestData.count)
        contentInfo.isByteRangeAccessSupported = false
      }
      if let dataRequest = loadingRequest.dataRequest {
        let offset = Int(dataRequest.requestedOffset)
        if offset < manifestData.count {
          let end = dataRequest.requestsAllDataToEndOfResource
            ? manifestData.count
            : min(manifestData.count, offset + dataRequest.requestedLength)
          dataRequest.respond(with: manifestData.subdata(in: offset ..< end))
        }
      }
      loadingRequest.finishLoading()
      return true
    }
  }

  private struct Representation {
    let baseURL: String
    let bandwidth: Int?
    let width: Int?
    let height: Int?
    let codecs: String?
    let frameRate: String?
  }

  private struct ParsedDASH {
    var videos: [Representation] = []
    var audios: [Representation] = []
  }

  private final class DASHParser: NSObject, XMLParserDelegate {
    private var parsed = ParsedDASH()
    private var currentContentType: String?
    private var currentMimeType: String?
    private var currentBandwidth: Int?
    private var currentWidth: Int?
    private var currentHeight: Int?
    private var currentCodecs: String?
    private var currentFrameRate: String?
    private var inRepresentation = false
    private var inBaseURL = false
    private var baseURLBuffer = ""

    func parse(_ data: Data) -> ParsedDASH? {
      let xml = XMLParser(data: data)
      xml.delegate = self
      guard xml.parse() else { return nil }
      return parsed
    }

    func parser(_: XMLParser, didStartElement elementName: String, namespaceURI _: String?, qualifiedName _: String?, attributes attributeDict: [String: String] = [:]) {
      switch elementName {
      case "AdaptationSet":
        currentContentType = attributeDict["contentType"]?.lowercased()
        currentMimeType = attributeDict["mimeType"]?.lowercased()
      case "Representation":
        inRepresentation = true
        currentBandwidth = attributeDict["bandwidth"].flatMap(Int.init)
        currentWidth = attributeDict["width"].flatMap(Int.init)
        currentHeight = attributeDict["height"].flatMap(Int.init)
        currentCodecs = attributeDict["codecs"]
        currentFrameRate = Self.normalizedFrameRate(attributeDict["frameRate"])
        if let mime = attributeDict["mimeType"]?.lowercased() {
          currentMimeType = mime
        }
      case "BaseURL" where inRepresentation:
        inBaseURL = true
        baseURLBuffer = ""
      default:
        break
      }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
      if inBaseURL {
        baseURLBuffer += string
      }
    }

    func parser(_: XMLParser, didEndElement elementName: String, namespaceURI _: String?, qualifiedName _: String?) {
      switch elementName {
      case "BaseURL":
        inBaseURL = false
      case "Representation":
        let baseURL = baseURLBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !baseURL.isEmpty {
          let rep = Representation(
            baseURL: baseURL,
            bandwidth: currentBandwidth,
            width: currentWidth,
            height: currentHeight,
            codecs: currentCodecs,
            frameRate: currentFrameRate,
          )
          if isAudioRepresentation {
            parsed.audios.append(rep)
          } else if isVideoRepresentation {
            parsed.videos.append(rep)
          }
        }
        inRepresentation = false
        baseURLBuffer = ""
        currentBandwidth = nil
        currentWidth = nil
        currentHeight = nil
        currentCodecs = nil
        currentFrameRate = nil
      case "AdaptationSet":
        currentContentType = nil
        currentMimeType = nil
      default:
        break
      }
    }

    private var isAudioRepresentation: Bool {
      currentContentType == "audio" || (currentMimeType?.hasPrefix("audio/") ?? false)
    }

    private var isVideoRepresentation: Bool {
      currentContentType == "video" || (currentMimeType?.hasPrefix("video/") ?? false) || (currentWidth != nil && currentHeight != nil)
    }

    private static func normalizedFrameRate(_ raw: String?) -> String? {
      guard let raw, !raw.isEmpty else { return nil }
      if raw.contains("/") {
        let parts = raw.split(separator: "/")
        guard parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den > 0 else { return nil }
        let fps = num / den
        return fps.rounded() == fps ? String(Int(fps)) : String(format: "%.3f", fps)
      }
      return Double(raw) != nil ? raw : nil
    }
  }
}
