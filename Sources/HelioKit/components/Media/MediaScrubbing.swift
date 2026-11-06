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

  /// "0:03 / 0:10", with hours only when the clip has them.
  static func label(_ time: Double, of duration: Double) -> String {
    let pattern: Duration.TimeFormatStyle.Pattern = duration >= 3600 ? .hourMinuteSecond : .minuteSecond
    func format(_ seconds: Double) -> String {
      Duration.seconds(max(0, seconds)).formatted(.time(pattern: pattern))
    }
    return "\(format(time)) / \(format(duration))"
  }
}

/// Where a scrub has moved the playhead, for the indicator.
struct ScrubPosition: Equatable {
  var time: Double
  var duration: Double

  var progress: Double {
    duration > 0 ? time / duration : 0
  }
}

/// Pauses a player while a swipe scrubs it and plays it again after, if it was playing.
/// Seeks are exact, so each one can take a moment on a stream; while one is running, only
/// the latest position is kept and sought next, so the frame keeps up with the finger.
/// Only the indicator reads `position`, so a scrub doesn't redraw the player's view.
@MainActor @Observable
final class VideoScrubber {
  private(set) var position: ScrubPosition?
  @ObservationIgnored private weak var player: AVPlayer?
  @ObservationIgnored private var start: Double = 0
  @ObservationIgnored private var duration: Double = 0
  @ObservationIgnored private var resumes = false
  @ObservationIgnored private var pending: CMTime?
  @ObservationIgnored private var seeking = false

  /// False when the video's length isn't known yet, so there's nothing to scrub.
  func begin(_ player: AVPlayer) -> Bool {
    guard let duration = player.currentItem?.duration.seconds, duration.isFinite, duration > 0 else { return false }
    self.player = player
    self.duration = duration
    start = player.currentTime().seconds
    resumes = player.rate != 0
    player.pause()
    return true
  }

  func update(translation: CGFloat, width: CGFloat) {
    guard player != nil else { return }
    let time = MediaScrub.time(from: start, translation: translation, width: width, duration: duration)
    pending = CMTime(seconds: time, preferredTimescale: 600)
    seekToPending()
    position = ScrubPosition(time: time, duration: duration)
  }

  func end() {
    position = nil
    guard let player else { return }
    // Seek straight to where the finger stopped, replacing any seek still running.
    if let pending {
      self.pending = nil
      player.seek(to: pending, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    if resumes {
      player.play()
    }
    self.player = nil
  }

  private func seekToPending() {
    guard !seeking, let player, let target = pending else { return }
    pending = nil
    seeking = true
    player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
      Task { @MainActor in
        self?.seeking = false
        self?.seekToPending()
      }
    }
  }
}

/// The playhead's place while scrubbing: a bar, with the time for videos.
struct ScrubIndicator: View {
  var position: ScrubPosition?
  var showsTime = true

  var body: some View {
    if let position {
      bar(position)
        .transition(.opacity)
    }
  }

  private func bar(_ position: ScrubPosition) -> some View {
    HStack(spacing: 10) {
      if showsTime {
        Text(MediaScrub.label(position.time, of: position.duration))
          .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
      }
      Capsule()
        .fill(.white.opacity(0.3))
        .frame(width: 120, height: 4)
        .overlay(alignment: .leading) {
          Capsule()
            .fill(.white)
            .frame(width: 120 * min(max(position.progress, 0), 1), height: 4)
        }
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .glassEffect(.regular, in: Capsule())
    .environment(\.colorScheme, .dark)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
