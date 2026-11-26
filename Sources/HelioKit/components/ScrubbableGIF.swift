import ImageIO
import SwiftUI
import UIKit

struct GIFTimeline: Equatable {
  let starts: [Double]
  let duration: Double

  static let defaultDelay = 0.1

  init(delays: [Double]) {
    var starts: [Double] = []
    var time = 0.0
    for delay in delays {
      starts.append(time)
      time += delay < 0.011 ? Self.defaultDelay : delay
    }
    self.starts = starts
    self.duration = time
  }

  init(source: CGImageSource) {
    self.init(delays: (0 ..< CGImageSourceGetCount(source)).map { index in
      let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
      let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
      return (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0
    })
  }

  func frame(at time: Double) -> Int {
    guard !starts.isEmpty else { return 0 }
    var low = 0
    var high = starts.count - 1
    while low < high {
      let mid = (low + high + 1) / 2
      if starts[mid] <= time {
        low = mid
      } else {
        high = mid - 1
      }
    }
    return low
  }
}

final class ScrubbableGIFView: UIView {
  private let source: CGImageSource?
  let timeline: GIFTimeline
  private let pixelSize: CGSize
  private var playhead = 0.0
  private var scrubStart = 0.0
  private(set) var isScrubbing = false
  private var shownFrame = -1
  private var wantedFrame = 0
  private var decoding = false
  private var displayLink: CADisplayLink?
  private var lastTick: CFTimeInterval?
  private var reportedFrame = -1
  var onPlayhead: ((Double) -> Void)?

  init(data: Data) {
    source = CGImageSourceCreateWithData(data as CFData, nil)
    timeline = source.map(GIFTimeline.init(source:)) ?? GIFTimeline(delays: [])
    let properties = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) } as? [CFString: Any]
    pixelSize = CGSize(width: properties?[kCGImagePropertyPixelWidth] as? Double ?? 0, height: properties?[kCGImagePropertyPixelHeight] as? Double ?? 0)
    super.init(frame: .zero)
    layer.contentsGravity = .resizeAspect
    clipsToBounds = true
    if !timeline.starts.isEmpty {
      show(frame: 0)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var intrinsicContentSize: CGSize {
    pixelSize
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    displayLink?.invalidate()
    displayLink = nil
    lastTick = nil
    guard window != nil, timeline.starts.count > 1 else { return }
    let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 60, preferred: 60)
    link.add(to: .main, forMode: .common)
    displayLink = link
  }

  @objc private func tick(_ link: CADisplayLink) {
    defer { lastTick = link.timestamp }
    guard !isScrubbing, let lastTick, timeline.duration > 0 else { return }
    playhead = (playhead + link.timestamp - lastTick).truncatingRemainder(dividingBy: timeline.duration)
    let frame = timeline.frame(at: playhead)
    show(frame: frame)
    if frame != reportedFrame {
      reportedFrame = frame
      onPlayhead?(playhead)
    }
  }

  func beginScrub() -> Bool {
    guard timeline.starts.count > 1 else { return false }
    isScrubbing = true
    scrubStart = playhead
    return true
  }

  func scrub(translation: CGFloat, width: CGFloat) {
    scrub(to: MediaScrub.time(from: scrubStart, translation: translation, width: width, duration: timeline.duration))
  }

  func scrub(to time: Double) {
    playhead = min(max(time, 0), timeline.duration)
    let frame = timeline.frame(at: playhead)
    show(frame: frame)
    reportedFrame = frame
    onPlayhead?(playhead)
  }

  func endScrub() {
    isScrubbing = false
  }

  private func show(frame: Int) {
    wantedFrame = frame
    guard !decoding, frame != shownFrame, let source else { return }
    decoding = true
    Task { [weak self] in
      let image = await decodeFrame(source, frame)
      guard let self else { return }
      decoding = false
      shownFrame = frame
      if let image {
        layer.contents = image
      }
      if wantedFrame != shownFrame {
        show(frame: wantedFrame)
      }
    }
  }

  deinit {
    displayLink?.invalidate()
  }
}

private func decodeFrame(_ source: CGImageSource, _ index: Int) async -> CGImage? {
  CGImageSourceCreateImageAtIndex(source, index, [kCGImageSourceShouldCacheImmediately: true, kCGImageSourceShouldCache: false] as CFDictionary)
}

@MainActor @Observable
final class GIFScrubber: MediaScrubbable {
  @ObservationIgnored fileprivate weak var view: ScrubbableGIFView? {
    didSet {
      guard view !== oldValue else { return }
      view?.onPlayhead = { [weak self, weak view] time in
        guard let view else { return }
        self?.position = ScrubPosition(time: time, duration: view.timeline.duration)
      }
    }
  }

  private(set) var position: ScrubPosition?

  func begin() -> Bool {
    view?.beginScrub() ?? false
  }

  func update(translation: CGFloat, width: CGFloat) {
    view?.scrub(translation: translation, width: width)
  }

  func scrub(toFraction fraction: Double) {
    guard let view else { return }
    view.scrub(to: fraction * view.timeline.duration)
  }

  func end() {
    view?.endScrub()
  }
}

struct ScrubbableGIF: UIViewRepresentable {
  let data: Data
  let scrubber: GIFScrubber

  func makeUIView(context: Context) -> ScrubbableGIFView {
    let view = ScrubbableGIFView(data: data)
    scrubber.view = view
    return view
  }

  func updateUIView(_ view: ScrubbableGIFView, context: Context) {
    scrubber.view = view
  }
}
