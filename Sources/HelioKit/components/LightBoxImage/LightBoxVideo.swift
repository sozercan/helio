//
//  LightBoxVideo.swift
//  Helio
//

import AVFoundation
import AVKit
import Combine
import Defaults
import SwiftUI

/// A video's playback on a lightbox page: playing while its page shows, with sound unless
/// "Default mute fullscreen videos" is on, scrubbed by a held drag or its progress bar, and
/// Picture in Picture.
@MainActor @Observable
final class LightBoxVideo: MediaScrubbable {
  let holder: VideoPlayerHolder
  /// The feed row's player, which that row takes back when the lightbox closes.
  @ObservationIgnored private let borrowed: Bool
  /// The layer the video draws in, kept here so Picture in Picture outlives the page's view.
  @ObservationIgnored let layerView = PlayerLayerHostView()
  @ObservationIgnored private let scrubber = VideoScrubber()
  @ObservationIgnored private var timeObserver: Any?
  @ObservationIgnored private var statusObservation: NSKeyValueObservation?
  /// Loop and failure observers, for whichever item the player has: a reload replaces it.
  @ObservationIgnored private var itemObservers: [NSObjectProtocol] = []
  @ObservationIgnored private var failureObservation: AnyCancellable?
  @ObservationIgnored private var active = false
  /// Released while in Picture in Picture: the observers go when it stops instead.
  @ObservationIgnored private var released = false
  @ObservationIgnored private var pictureInPicture: AVPictureInPictureController?
  @ObservationIgnored private var pictureInPictureDelegate: PictureInPictureDelegate?
  /// Closes the lightbox, so the feed is usable while the video floats.
  @ObservationIgnored var onPictureInPictureStart: (() -> Void)?

  private(set) var position: ScrubPosition?
  private(set) var isPlaying = false
  /// It didn't load, and retrying on its own didn't help: the page offers to try again.
  private(set) var failed = false
  var isMuted: Bool {
    didSet { player?.isMuted = isMuted }
  }

  var player: AVPlayer? {
    holder.player
  }

  var canPictureInPicture: Bool {
    pictureInPicture != nil
  }

  init(video: SharedVideo, holder: VideoPlayerHolder?) {
    self.holder = holder ?? VideoPlayerHolder(url: video.url)
    borrowed = holder != nil
    isMuted = Defaults[.VideoDefSettings].mute
    layerView.playerLayer.videoGravity = .resizeAspect
    layerView.playerLayer.player = player
    guard let player else { return }
    statusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
      let playing = player.timeControlStatus != .paused
      Task { @MainActor in self?.isPlaying = playing }
    }
    timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
      MainActor.assumeIsolated { self?.show(time) }
    }
    let loop = Defaults[.VideoDefSettings].loop
    player.actionAtItemEnd = loop ? .none : .pause
    // Kept until it's released, Picture in Picture included, so it loops there too.
    let center = NotificationCenter.default
    itemObservers = [
      center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak player] note in
        guard loop, let player, note.object as? AVPlayerItem === player.currentItem else { return }
        player.seek(to: .zero)
      },
      center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self, weak player] note in
        guard let player, note.object as? AVPlayerItem === player.currentItem else { return }
        MainActor.assumeIsolated { self?.recover(failedToEnd: true) }
      },
      // Stalls usually recover once the buffer refills: only one still stuck is reloaded.
      center.addObserver(forName: .AVPlayerItemPlaybackStalled, object: nil, queue: .main) { [weak self, weak player] note in
        guard let player, let item = note.object as? AVPlayerItem, item === player.currentItem else { return }
        Task { @MainActor [weak self, weak player] in
          try? await Task.sleep(for: .seconds(4))
          guard let player, player.currentItem === item, player.timeControlStatus == .waitingToPlayAtSpecifiedRate else { return }
          self?.recover(failedToEnd: true)
        }
      },
    ]
    failureObservation = self.holder.$itemFailed.removeDuplicates().filter(\.self).sink { [weak self] _ in
      MainActor.assumeIsolated { self?.recover() }
    }
    if AVPictureInPictureController.isPictureInPictureSupported() {
      let controller = AVPictureInPictureController(playerLayer: layerView.playerLayer)
      let delegate = PictureInPictureDelegate(video: self)
      controller?.delegate = delegate
      pictureInPicture = controller
      pictureInPictureDelegate = delegate
    }
  }

  private func show(_ time: CMTime) {
    guard let duration = player?.currentItem?.duration.seconds, duration.isFinite, duration > 0 else { return }
    let position = ScrubPosition(time: min(max(time.seconds, 0), duration), duration: duration)
    if self.position != position {
      self.position = position
    }
  }

  /// A failed item: loads it again while the holder's retries last, then offers to try again.
  /// A borrowed player's feed row reloads it too, so only an item still failed is reloaded here,
  /// and one that stopped short of its end or stalled is left to the row.
  private func recover(failedToEnd: Bool = false) {
    guard failedToEnd ? !borrowed : holder.hasFailed else { return }
    if holder.reload() {
      if active {
        player?.play()
      }
    } else {
      failed = true
    }
  }

  /// Tries again after it failed, when asked.
  func retry() {
    failed = false
    holder.retry()
    if active {
      player?.play()
    }
  }

  /// Plays from the start a video that played to its end without looping.
  private func play(_ player: AVPlayer) {
    if let duration = player.currentItem?.duration.seconds, duration.isFinite, duration - player.currentTime().seconds < 0.1 {
      player.seek(to: .zero)
    }
    player.play()
  }

  /// Its page is showing: play it.
  func activate() {
    guard !active, let player else { return }
    active = true
    let settings = Defaults[.VideoDefSettings]
    player.isMuted = isMuted
    player.volume = 1
    // Coming back to a page whose video failed loads it again rather than replaying the failure.
    if holder.hasFailed {
      recover()
    }
    play(player)
    PictureInPicture.shared.fullscreenPlayers += 1
    if settings.pauseBGAudioOnFullscreen {
      scheduleAudioMixing(false)
    }
  }

  /// Back in the app, its page still showing: play on, as the system paused it.
  func resume() {
    guard active, let player else { return }
    if holder.hasFailed {
      recover()
    }
    play(player)
  }

  /// Its page went away, or the lightbox closed: stop it, unless it went on in Picture in Picture.
  func deactivate() {
    guard active, let player else { return }
    active = false
    PictureInPicture.shared.fullscreenPlayers -= 1
    guard !PictureInPicture.shared.isPlaying(player) else { return }
    player.pause()
    if borrowed {
      player.volume = 0
    }
    if Defaults[.VideoDefSettings].pauseBGAudioOnFullscreen, PictureInPicture.shared.fullscreenPlayers == 0 {
      scheduleAudioMixing(true)
    }
  }

  /// Done with it. A borrowed player stays with its feed row, so its observers go now, or once
  /// Picture in Picture stops.
  func release() {
    deactivate()
    guard !PictureInPicture.shared.isPlaying(player) else {
      released = true
      return
    }
    if let timeObserver {
      player?.removeTimeObserver(timeObserver)
    }
    timeObserver = nil
    statusObservation?.invalidate()
    itemObservers.forEach { NotificationCenter.default.removeObserver($0) }
    itemObservers = []
    failureObservation = nil
    layerView.playerLayer.player = nil
  }

  func togglePlayback() {
    guard let player else { return }
    if isPlaying {
      player.pause()
    } else {
      play(player)
    }
  }

  func startPictureInPicture() {
    pictureInPicture?.startPictureInPicture()
  }

  fileprivate func pictureInPictureStarted() {
    PictureInPicture.shared.begin(holder, owner: self)
    onPictureInPictureStart?()
  }

  fileprivate func pictureInPictureStopped() {
    PictureInPicture.shared.end(self)
    if released {
      release()
    }
  }

  // MARK: MediaScrubbable

  func begin() -> Bool {
    guard let player else { return false }
    return scrubber.begin(player)
  }

  func update(translation: CGFloat, width: CGFloat) {
    scrubber.update(translation: translation, width: width)
  }

  func scrub(toFraction fraction: Double) {
    scrubber.scrub(toFraction: fraction)
  }

  func end() {
    scrubber.end()
  }
}

/// The controller holds its delegate weakly, so the video keeps it.
private final class PictureInPictureDelegate: NSObject, AVPictureInPictureControllerDelegate {
  weak var video: LightBoxVideo?

  init(video: LightBoxVideo) {
    self.video = video
  }

  func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
    Task { @MainActor in video?.pictureInPictureStarted() }
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
    Task { @MainActor in video?.pictureInPictureStopped() }
  }

  /// The lightbox closed when Picture in Picture started, so there's nothing to go back to.
  func pictureInPictureController(_ controller: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
    completionHandler(false)
  }
}

/// A video page of the lightbox, its poster showing until the video can play.
struct LightBoxVideoPage: View {
  let video: LightBoxVideo
  @ObservedObject var holder: VideoPlayerHolder
  var posterURL: URL?
  var label: String?
  /// The page showing. The pages beside it keep their failure to themselves until they show.
  var selected: Bool
  var onTap: () -> Void
  var onSwipe: ((Int) -> Void)?
  var onHold: (LightBoxScrub) -> Void
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    LightBoxPlayerView(video: video, onTap: onTap, onSwipe: onSwipe, onHold: onHold)
      .onChange(of: scenePhase) { _, phase in
        if phase == .active {
          video.resume()
        }
      }
      .overlay {
        if !holder.isReadyToPlay, let posterURL {
          URLImage(url: posterURL)
            .scaledToFit()
            .allowsHitTesting(false)
        }
      }
      .overlay {
        if video.failed, selected {
          VStack(spacing: 12) {
            Text("Couldn't play this video")
              .fontSize(16, .semibold)
            Button("Try Again") { video.retry() }
              .buttonStyle(.glass)
          }
          .foregroundStyle(.white)
          .padding(20)
          .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
      }
      .accessibilityIgnoresInvertColors()
      // One element, which the lightbox gives the page's place and paging. A failure is read in
      // its label, and Try Again is one of its actions.
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(video.failed && selected ? "\(label ?? "Video"), couldn't play this video" : label ?? "Video")
      .accessibilityActions {
        if video.failed, selected {
          Button("Try Again") { video.retry() }
        }
      }
      .frame(width: .screenW)
      .frame(maxHeight: .infinity)
      .preferredColorScheme(.dark)
      .statusBar(hidden: true)
  }
}

/// Shows the video's layer, with the page's taps, held drags and trackpad swipes.
private struct LightBoxPlayerView: UIViewRepresentable {
  let video: LightBoxVideo
  var onTap: () -> Void
  var onSwipe: ((Int) -> Void)?
  var onHold: (LightBoxScrub) -> Void

  func makeUIView(context: Context) -> UIView {
    let view = UIView()
    let layerView = video.layerView
    layerView.removeFromSuperview()
    layerView.frame = view.bounds
    layerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(layerView)

    let gestures = context.coordinator.gestures
    gestures.install(on: view)
    let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
    if let hold = gestures.hold {
      tap.require(toFail: hold)
    }
    view.addGestureRecognizer(tap)
    update(context.coordinator)
    return view
  }

  func updateUIView(_ view: UIView, context: Context) {
    update(context.coordinator)
  }

  private func update(_ coordinator: Coordinator) {
    coordinator.onTap = onTap
    coordinator.gestures.onSwipe = onSwipe
    coordinator.gestures.onHold = onHold
  }

  static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
    view.subviews.forEach { $0.removeFromSuperview() }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  @MainActor
  final class Coordinator: NSObject {
    let gestures = LightBoxGestures()
    var onTap: (() -> Void)?

    @objc func handleTap() {
      onTap?()
    }
  }
}
