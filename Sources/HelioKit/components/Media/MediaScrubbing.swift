import AVFoundation
import SwiftUI

enum MediaScrub {
  static let maxSecondsPerWidth: Double = 60

  static func time(from start: Double, translation: CGFloat, width: CGFloat, duration: Double) -> Double {
    guard duration > 0, width > 0 else { return start }
    let span = min(duration, maxSecondsPerWidth)
    return min(max(start + Double(translation / width) * span, 0), duration)
  }

  static func timestamp(_ seconds: Double) -> String {
    Duration.seconds(max(0, seconds)).formatted(.time(pattern: .minuteSecond))
  }

  static func timestamps(_ time: Double, of duration: Double) -> (elapsed: String, remaining: String) {
    (timestamp(time.rounded(.down)), "-" + timestamp((duration - time).rounded(.up)))
  }
}

struct ScrubPosition: Equatable {
  var time: Double
  var duration: Double

  var progress: Double {
    duration > 0 ? time / duration : 0
  }
}

@MainActor
protocol MediaScrubbable: AnyObject {
  var position: ScrubPosition? { get }
  func begin() -> Bool
  func update(translation: CGFloat, width: CGFloat)
  func scrub(toFraction fraction: Double)
  func end()
}

struct MediaProgressBar: View {
  let scrubber: any MediaScrubbable
  @State private var dragging = false
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

@MainActor
final class VideoScrubber {
  static let maxTolerance = 0.5

  private weak var player: AVPlayer?
  private var start: Double = 0
  private var duration: Double = 0
  private var resumes = false
  private var target: Double?
  private var sought: (time: Double, exact: Bool)?
  private var seeking = false

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

  func scrub(toFraction fraction: Double) {
    guard player != nil else { return }
    target = min(max(fraction, 0), 1) * duration
    seekToTarget()
  }

  func end() {
    guard let player else { return }
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
