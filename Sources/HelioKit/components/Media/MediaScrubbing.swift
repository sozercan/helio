import AVFoundation
import SwiftUI

/// Swiping sideways across a fullscreen video or GIF scrubs through it, as Apollo did.
enum MediaScrub {
  /// The most time a swipe across the whole window covers. Shorter clips span the whole width,
  /// so a GIF can be scrubbed end to end in one swipe while a long video still moves finely.
  static let maxSecondsPerWidth: Double = 60

  /// Where a swipe of `translation` points, started at `start`, puts the playhead.
  static func time(from start: Double, translation: CGFloat, width: CGFloat, duration: Double) -> Double {
    guard duration > 0, width > 0 else { return start }
    let span = min(duration, maxSecondsPerWidth)
    return min(max(start + Double(translation / width) * span, 0), duration)
  }

  /// "0:03", whole seconds as the video player shows them.
  static func timestamp(_ seconds: Double) -> String {
    Duration.seconds(max(0, seconds)).formatted(.time(pattern: .minuteSecond))
  }

  /// Elapsed time rounds down and the time left rounds up, so the two add up to the length.
  static func timestamps(_ time: Double, of duration: Double) -> (elapsed: String, remaining: String) {
    (timestamp(time.rounded(.down)), "-" + timestamp((duration - time).rounded(.up)))
  }
}

/// Where a scrub has moved the playhead.
struct ScrubPosition: Equatable {
  var time: Double
  var duration: Double

  var progress: Double {
    duration > 0 ? time / duration : 0
  }
}

/// A GIF's progress, laid out like the video player's bar: the track, with the elapsed time under
/// its leading end and the time left under its trailing end. Dragging along it scrubs.
struct GIFProgressBar: View {
  let scrubber: GIFScrubber
  @State private var dragging = false
  /// Resets when the drag ends or is cancelled; a cancelled drag skips `onEnded`.
  @GestureState private var touching = false

  var body: some View {
    if let position = scrubber.position {
      VStack(spacing: 6) {
        GeometryReader { geometry in
          let width = geometry.size.width
          Capsule()
            .fill(.white.opacity(0.3))
            .overlay(alignment: .leading) {
              Capsule()
                .fill(.white)
                .frame(width: width * min(max(position.progress, 0), 1))
            }
            .frame(height: dragging ? 10 : 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
              DragGesture(minimumDistance: 0)
                .updating($touching) { _, touching, _ in touching = true }
                .onChanged { value in
                  if !dragging {
                    guard scrubber.begin() else { return }
                    withAnimation(.easeOut(duration: 0.15)) { dragging = true }
                  }
                  scrubber.scrub(toFraction: width > 0 ? value.location.x / width : 0)
                }
                .onEnded { _ in endDrag() },
            )
        }
        .frame(height: 24)
        let times = MediaScrub.timestamps(position.time, of: position.duration)
        HStack {
          Text(times.elapsed)
          Spacer()
          Text(times.remaining)
        }
        .font(.caption.weight(.medium).monospacedDigit())
        .foregroundStyle(.white.opacity(0.8))
      }
      .onChange(of: touching) { _, touching in
        if !touching {
          endDrag()
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Playback position")
      .accessibilityValue("\(MediaScrub.timestamp(position.time)) of \(MediaScrub.timestamp(position.duration))")
      .accessibilityAdjustableAction { direction in
        let step = direction == .increment ? 0.1 : -0.1
        guard scrubber.begin() else { return }
        scrubber.scrub(toFraction: min(max(position.progress + step, 0), 1))
        scrubber.end()
      }
    }
  }

  private func endDrag() {
    guard dragging else { return }
    scrubber.end()
    withAnimation(.easeOut(duration: 0.15)) { dragging = false }
  }
}

/// Pauses a player while a swipe scrubs it, and plays it again after if it was playing.
///
/// An exact seek on a stream takes about a fifth of a second, so seeking exactly to each finger
/// position shows only a few frames a second. While the finger moves, a seek may land anywhere
/// within how far the finger went since the last one, which takes a few hundredths of a second
/// and is no less accurate than the finger. When the finger rests or lifts, an exact seek settles
/// it. Only the latest position is kept while a seek runs, so seeks never queue up.
@MainActor
final class VideoScrubber {
  /// The most a seek may miss by, however fast the finger moves.
  static let maxTolerance = 0.5

  private weak var player: AVPlayer?
  private var start: Double = 0
  private var duration: Double = 0
  private var resumes = false
  /// Where the finger points.
  private var target: Double?
  /// The last seek's time, and whether it was exact.
  private var sought: (time: Double, exact: Bool)?
  private var seeking = false

  /// False when the video's length isn't known yet, so there's nothing to scrub.
  func begin(_ player: AVPlayer) -> Bool {
    guard let duration = player.currentItem?.duration.seconds, duration.isFinite, duration > 0 else { return false }
    self.player = player
    self.duration = duration
    start = player.currentTime().seconds
    sought = (start, true)
    target = nil
    resumes = player.rate != 0
    player.pause()
    return true
  }

  func update(translation: CGFloat, width: CGFloat) {
    guard player != nil else { return }
    target = MediaScrub.time(from: start, translation: translation, width: width, duration: duration)
    seekToTarget()
  }

  func end() {
    guard let player else { return }
    // Settle exactly where the finger lifted, replacing any seek still running.
    if let target, sought?.time != target || sought?.exact != true {
      player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    if resumes {
      player.play()
    }
    self.player = nil
    target = nil
  }

  private func seekToTarget() {
    guard !seeking, let player, let target else { return }
    let resting = sought?.time == target
    if resting, sought?.exact == true {
      return
    }
    let tolerance = resting ? 0 : min(abs(target - (sought?.time ?? target)), Self.maxTolerance)
    let window = CMTime(seconds: tolerance, preferredTimescale: 600)
    sought = (target, tolerance == 0)
    seeking = true
    player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: window, toleranceAfter: window) { [weak self] _ in
      Task { @MainActor in
        self?.seeking = false
        self?.seekToTarget()
      }
    }
  }
}
