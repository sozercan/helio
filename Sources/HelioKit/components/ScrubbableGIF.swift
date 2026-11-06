import ImageIO
import SwiftUI
import UIKit

/// A GIF's frame timing, read from its data: when each frame starts and how long the loop is.
struct GIFTimeline: Equatable {
  /// Each frame's start time, from 0.
  let starts: [Double]
  let duration: Double

  /// Browsers show frames with no delay, or a near-zero one, for a tenth of a second.
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

  /// The frame showing at `time`.
  func frame(at time: Double) -> Int {
    guard !starts.isEmpty else { return 0 }
    // The last frame starting at or before `time`.
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

/// Plays a GIF with a playhead that can be moved, which Gifu has no way to do. Frames are decoded
/// one at a time off the main thread, so memory stays at about one frame whatever the GIF's length.
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

  /// Data ImageIO can't read leaves it empty, as Gifu would.
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

  /// SwiftUI sizes it from this, so `.scaledToFit()` keeps the GIF's shape.
  override var intrinsicContentSize: CGSize {
    pixelSize
  }

  /// The display link holds its target, so it only runs while the view is in a window.
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
    show(frame: timeline.frame(at: playhead))
  }

  /// False for a GIF with one frame, which has nothing to scrub.
  func beginScrub() -> Bool {
    guard timeline.starts.count > 1 else { return false }
    isScrubbing = true
    scrubStart = playhead
    return true
  }

  func scrub(translation: CGFloat, width: CGFloat) -> ScrubPosition {
    playhead = MediaScrub.time(from: scrubStart, translation: translation, width: width, duration: timeline.duration)
    show(frame: timeline.frame(at: playhead))
    return ScrubPosition(time: playhead, duration: timeline.duration)
  }

  /// Plays on from where the scrub left it.
  func endScrub() {
    isScrubbing = false
  }

  /// Decodes `frame` and shows it. While a decode runs, only the latest frame asked for is kept.
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

/// Async and not on an actor, so the decode runs off the main thread.
private func decodeFrame(_ source: CGImageSource, _ index: Int) async -> CGImage? {
  CGImageSourceCreateImageAtIndex(source, index, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
}

/// Connects the lightbox's swipe to the GIF it shows. The view registers itself when it's made.
/// Only the indicator reads `position`, so a scrub doesn't redraw the rest of the lightbox.
@MainActor @Observable
final class GIFScrubber {
  @ObservationIgnored fileprivate weak var view: ScrubbableGIFView?
  private(set) var position: ScrubPosition?

  func begin() -> Bool {
    view?.beginScrub() ?? false
  }

  func update(translation: CGFloat, width: CGFloat) {
    position = view?.scrub(translation: translation, width: width)
  }

  func end() {
    view?.endScrub()
    position = nil
  }
}

/// A GIF the lightbox can scrub. Made once per GIF: the body runs again on every lightbox update.
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
