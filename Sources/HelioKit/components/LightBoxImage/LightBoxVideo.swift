import AVFoundation
import AVKit
import Combine
import Defaults
import SwiftUI

@MainActor @Observable
final class LightBoxVideo: MediaScrubbable {
  let holder: VideoPlayerHolder
  @ObservationIgnored private let borrowed: Bool
  @ObservationIgnored let layerView = PlayerLayerHostView()
  @ObservationIgnored private let scrubber = VideoScrubber()
  @ObservationIgnored private var timeObserver: Any?
  @ObservationIgnored private var statusObservation: NSKeyValueObservation?
  @ObservationIgnored private var itemObservers: [NSObjectProtocol] = []
  @ObservationIgnored private var failureObservation: AnyCancellable?
  @ObservationIgnored private var active = false
  @ObservationIgnored private var wantsPlayback = false
  @ObservationIgnored private var released = false
  @ObservationIgnored private var pictureInPicture: AVPictureInPictureController?
  @ObservationIgnored private var pictureInPictureDelegate: PictureInPictureDelegate?
  @ObservationIgnored var onPictureInPictureStart: (() -> Void)?

  private(set) var position: ScrubPosition?
  private(set) var isPlaying = false
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
    self.holder = holder ?? VideoPlayerHolder(url: video.url, dashURL: video.dashURL, fallbackURL: video.fallbackURL)
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

  private func recover(failedToEnd: Bool = false) {
    guard failedToEnd ? !borrowed : holder.hasFailed else { return }
    let started = holder.reload { [weak self] in
      guard let self, self.active, self.wantsPlayback else { return }
      self.player?.play()
    }
    if !started {
      failed = true
    }
  }

  func retry() {
    failed = false
    wantsPlayback = true
    holder.retry { [weak self] in
      guard let self, self.active, self.wantsPlayback else { return }
      self.player?.play()
    }
  }

  private func play(_ player: AVPlayer) {
    if let duration = player.currentItem?.duration.seconds, duration.isFinite, duration - player.currentTime().seconds < 0.1 {
      player.seek(to: .zero)
    }
    player.play()
  }

  func activate() {
    guard !active, let player else { return }
    active = true
    wantsPlayback = true
    let settings = Defaults[.VideoDefSettings]
    player.isMuted = isMuted
    player.volume = 1
    if holder.hasFailed {
      recover()
    }
    play(player)
    PictureInPicture.shared.fullscreenPlayers += 1
    if settings.pauseBGAudioOnFullscreen {
      scheduleAudioMixing(false)
    }
  }

  func resume() {
    guard active, let player else { return }
    wantsPlayback = true
    if holder.hasFailed {
      recover()
    }
    play(player)
  }

  func deactivate() {
    guard active, let player else { return }
    active = false
    wantsPlayback = false
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
      wantsPlayback = false
      player.pause()
    } else {
      wantsPlayback = true
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

  func pictureInPictureController(_ controller: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
    completionHandler(false)
  }
}

struct LightBoxVideoPage: View {
  let video: LightBoxVideo
  @ObservedObject var holder: VideoPlayerHolder
  var width: CGFloat
  var posterURL: URL?
  var label: String?
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
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(video.failed && selected ? "\(label ?? "Video"), couldn't play this video" : label ?? "Video")
      .accessibilityActions {
        if video.failed, selected {
          Button("Try Again") { video.retry() }
        }
      }
      .frame(width: width)
      .frame(maxHeight: .infinity)
      .preferredColorScheme(.dark)
      .statusBar(hidden: true)
  }
}

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
