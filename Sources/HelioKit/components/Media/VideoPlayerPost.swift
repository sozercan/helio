import AVFoundation
import AVKit
import Combine
import CoreMedia
import Defaults
import SwiftUI

final class VideoPlayerHolder: ObservableObject {
  let player: AVPlayer?
  @Published private(set) var isReadyToPlay = false
  @Published private(set) var itemFailed = false
  private let url: URL?
  private let dashURL: URL?
  private let fallbackURL: URL?
  private let recoverPlaylist: @Sendable (URL, URL?, URL?) async -> RedditVideoPlaylistRecovery.RecoveredSource?
  private var recoveredSource: RedditVideoPlaylistRecovery.RecoveredSource?
  private var resourceLoaderDelegate: AVAssetResourceLoaderDelegate?
  private var attemptedRecovery = false
  private var recoveryTask: Task<Void, Never>?
  private var pendingReloadCallbacks: [@MainActor () -> Void] = []
  private var statusObservation: NSKeyValueObservation?
  private var reloads = 0
  private let maxReloads = 2

  init(
    url: URL?,
    dashURL: URL? = nil,
    fallbackURL: URL? = nil,
    recoverPlaylist: @escaping @Sendable (URL, URL?, URL?) async -> RedditVideoPlaylistRecovery.RecoveredSource? = { hls, dash, fallback in
      await RedditVideoPlaylistRecovery.recover(hlsURL: hls, dashURL: dash, fallbackURL: fallback)
    },
  ) {
    self.url = url
    self.dashURL = dashURL
    self.fallbackURL = fallbackURL
    self.recoverPlaylist = recoverPlaylist
    if let url {
      let p = AVPlayer(playerItem: AVPlayerItem(url: url))
      p.volume = 0.0
      player = p
    } else {
      player = nil
    }
    observeCurrentItem()
  }

  @MainActor
  @discardableResult
  func reload(onItemReplaced: (@MainActor () -> Void)? = nil) -> Bool {
    guard let player, let url else { return false }

    if recoveryTask != nil {
      if let onItemReplaced {
        pendingReloadCallbacks.append(onItemReplaced)
      }
      return true
    }

    guard reloads < maxReloads else { return false }
    reloads += 1
    isReadyToPlay = false
    itemFailed = false

    if !attemptedRecovery, RedditVideoPlaylistRecovery.isRedditHLSPlaylist(url) {
      attemptedRecovery = true
      if let onItemReplaced {
        pendingReloadCallbacks.append(onItemReplaced)
      }
      let dashURL = dashURL
      let fallbackURL = fallbackURL
      let recover = recoverPlaylist
      recoveryTask = Task { @MainActor [weak self] in
        let replacement = await recover(url, dashURL, fallbackURL)
        guard let self, !Task.isCancelled, let player = self.player else { return }
        self.recoveryTask = nil
        let callbacks = self.pendingReloadCallbacks
        self.pendingReloadCallbacks = []
        self.recoveredSource = replacement
        let shouldPlay = player.timeControlStatus != .paused || player.rate > 0
        if let replacement {
          let (item, delegate) = RedditVideoPlaylistRecovery.makePlayerItem(for: replacement)
          self.resourceLoaderDelegate = delegate
          player.replaceCurrentItem(with: item)
        } else {
          self.resourceLoaderDelegate = nil
          player.replaceCurrentItem(with: AVPlayerItem(url: url))
        }
        self.observeCurrentItem()
        callbacks.forEach { $0() }
        if shouldPlay {
          player.play()
        }
      }
      return true
    }

    if case .manifest = recoveredSource, let fallbackURL {
      recoveredSource = .directURL(fallbackURL)
      resourceLoaderDelegate = nil
      player.replaceCurrentItem(with: AVPlayerItem(url: fallbackURL))
    } else if let recoveredSource {
      let (item, delegate) = RedditVideoPlaylistRecovery.makePlayerItem(for: recoveredSource)
      resourceLoaderDelegate = delegate
      player.replaceCurrentItem(with: item)
    } else {
      resourceLoaderDelegate = nil
      player.replaceCurrentItem(with: AVPlayerItem(url: url))
    }
    observeCurrentItem()
    onItemReplaced?()
    return true
  }

  @MainActor
  func retry(onItemReplaced: (@MainActor () -> Void)? = nil) {
    recoveryTask?.cancel()
    recoveryTask = nil
    pendingReloadCallbacks = []
    reloads = 0
    attemptedRecovery = false
    recoveredSource = nil
    resourceLoaderDelegate = nil
    reload(onItemReplaced: onItemReplaced)
  }

  var hasFailed: Bool {
    player?.status == .failed || player?.currentItem?.status == .failed
  }

  private func observeCurrentItem() {
    statusObservation = player?.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
      let ready = item.status == .readyToPlay
      let failed = item.status == .failed
      Task { @MainActor [weak self] in
        self?.isReadyToPlay = ready
        self?.itemFailed = failed
      }
    }
  }

  deinit {
    recoveryTask?.cancel()
    statusObservation?.invalidate()
    player?.pause()
    player?.replaceCurrentItem(with: nil)
  }
}

struct SharedVideo: Equatable {
  static func == (lhs: SharedVideo, rhs: SharedVideo) -> Bool {
    lhs.url == rhs.url && lhs.size == rhs.size && lhs.dashURL == rhs.dashURL && lhs.fallbackURL == rhs.fallbackURL
  }

  var url: URL
  var size: CGSize
  var posterURL: URL?
  var dashURL: URL?
  var fallbackURL: URL?

  static func get(url: URL, size: CGSize, posterURL: URL? = nil, dashURL: URL? = nil, fallbackURL: URL? = nil) -> SharedVideo {
    SharedVideo(url: url, size: size, posterURL: posterURL, dashURL: dashURL, fallbackURL: fallbackURL)
  }

  init(url: URL, size: CGSize, posterURL: URL? = nil, dashURL: URL? = nil, fallbackURL: URL? = nil) {
    self.url = url
    self.size = size
    self.posterURL = posterURL
    self.dashURL = dashURL
    self.fallbackURL = fallbackURL
  }
}

final class VideoObserverBag {
  private var tokens: [NSObjectProtocol] = []
  func set(_ newTokens: [NSObjectProtocol]) {
    removeAll()
    tokens = newTokens
  }

  func removeAll() {
    tokens.forEach { NotificationCenter.default.removeObserver($0) }
    tokens = []
  }

  deinit { removeAll() }
}

struct VideoPlayerPost: View, Equatable {
  static func == (lhs: VideoPlayerPost, rhs: VideoPlayerPost) -> Bool {
    lhs.url == rhs.url && lhs.sharedVideo == rhs.sharedVideo && lhs.contentWidth == rhs.contentWidth && lhs.compact == rhs.compact && lhs.cornerRadius == rhs.cornerRadius && lhs.maxMediaHeightScreenPercentage == rhs.maxMediaHeightScreenPercentage
  }

  weak var controller: UIViewController?
  var sharedVideo: SharedVideo?
  let markAsSeen: (() async -> Void)?
  var compact = false
  var contentWidth: CGFloat
  var url: URL
  var size: CGSize
  var maxMediaHeightScreenPercentage: CGFloat
  var cornerRadius: CGFloat = 12
  var lightboxPost: LightBoxPost
  var feedPost: PostHelioData?
  @State private var fullscreen = false
  @State private var lightbox: LightBoxTimeline?
  @Environment(\.feedPostsSource) private var feed
  @Environment(\.lightBoxPresenter) private var presenter

  private var inLightbox: Bool {
    lightbox != nil || presenter?.isShowing(holder) == true
  }

  @Default(.VideoDefSettings) private var videoDefSettings
  @Environment(\.scenePhase) private var scenePhase
  @State private var observerBag = VideoObserverBag()
  @State private var isVisible = false
  @State private var systemAutoplay = UIAccessibility.isVideoAutoplayEnabled
  @StateObject private var holder: VideoPlayerHolder

  private var autoPlayVideos: Bool {
    videoDefSettings.autoPlay && systemAutoplay
  }

  private var loopVideos: Bool {
    videoDefSettings.loop
  }

  private var isFullscreen: Bool {
    fullscreen || inLightbox
  }

  private func open(_ sharedVideo: SharedVideo) {
    let own = lightboxPost.pages([.video(sharedVideo, holder: holder)])
    let timeline = LightBoxTimeline.around(feedPost, in: feed, own: own, start: 0)
    if let presenter {
      presenter.timeline = timeline
    } else {
      lightbox = timeline
    }
  }

  init(controller: UIViewController?, cachedVideo: SharedVideo?, markAsSeen: (() async -> Void)?, compact: Bool = false, contentWidth: CGFloat, url: URL, maxMediaHeightScreenPercentage: CGFloat, cornerRadius: CGFloat = 12, lightboxPost: LightBoxPost? = nil, feedPost: PostHelioData? = nil) {
    self.controller = controller
    self.sharedVideo = cachedVideo
    self.markAsSeen = markAsSeen
    self.compact = compact
    self.contentWidth = contentWidth
    self.url = url
    self.size = cachedVideo?.size ?? .zero
    self.maxMediaHeightScreenPercentage = maxMediaHeightScreenPercentage
    self.cornerRadius = cornerRadius
    self.lightboxPost = lightboxPost ?? LightBoxPost(key: "opened", markAsSeen: markAsSeen)
    self.feedPost = feedPost
    _holder = StateObject(wrappedValue: VideoPlayerHolder(url: cachedVideo != nil ? url : nil, dashURL: cachedVideo?.dashURL, fallbackURL: cachedVideo?.fallbackURL))
  }

  var body: some View {
    let maxHeight: CGFloat = (maxMediaHeightScreenPercentage / 100) * .screenH
    let knownSize = size.width > 0 && size.height > 0
    let sourceWidth = knownSize ? size.width : contentWidth
    let sourceHeight = knownSize ? size.height : contentWidth
    let propHeight = (contentWidth * sourceHeight) / sourceWidth
    let finalHeight = maxMediaHeightScreenPercentage != 110 ? Double(min(maxHeight, propHeight)) : Double(propHeight)

    if let sharedVideo, let player = holder.player {
      if let controller {
        AVPlayerRepresentable(fullscreen: $fullscreen, autoPlayVideos: autoPlayVideos, player: player, aspect: .resizeAspectFill, controller: controller)
          .frame(width: compact ? scaledCompactModeThumbSize() : contentWidth, height: compact ? scaledCompactModeThumbSize() : CGFloat(finalHeight))
          .accessibilityIgnoresInvertColors()
          .mask(RR(cornerRadius, Color.black))
          .allowsHitTesting(false)
          .contentShape(Rectangle())
          .onTapGesture {
            if markAsSeen != nil {
              Task(priority: .background) { await markAsSeen?() }
            }
            withAnimation {
              fullscreen = true
            }
          }
      } else {
        ZStack {
          Group {
            if isVisible, !inLightbox {
              InlinePlayerLayer(player: player)
            } else {
              Color.clear
            }
          }
          .frame(width: compact ? scaledCompactModeThumbSize() : contentWidth, height: compact ? scaledCompactModeThumbSize() : CGFloat(finalHeight))
          .accessibilityIgnoresInvertColors()
          .overlay {
            if !holder.isReadyToPlay, let posterURL = sharedVideo.posterURL {
              URLImage(url: posterURL)
                .allowsHitTesting(false)
            }
          }
          .clipped()
          .fixedSize()
          .mask(RR(cornerRadius, Color.black))
          .allowsHitTesting(false)
          .contentShape(Rectangle())
          .highPriorityGesture(TapGesture().onEnded { _ in open(sharedVideo) })
          .allowsHitTesting(false)
          .mask(RR(cornerRadius, Color.black))
          .overlay(
            Color.clear
              .contentShape(Rectangle())
              .onTapGesture { open(sharedVideo) },
          )

          Image(systemName: "play.fill").foregroundColor(.white.opacity(0.75)).fontSize(32).shadow(color: .black.opacity(0.45), radius: 12, y: 8).opacity(autoPlayVideos ? 0 : 1).allowsHitTesting(false)
        }
        .onAppear {
          isVisible = true
          observePlayback(player)
          if holder.hasFailed {
            reload(player)
          }
          if autoPlayVideos {
            player.play()
          }
        }
        .onChange(of: holder.itemFailed) { _, failed in
          if failed, isVisible {
            reload(player)
          }
        }
        .onChange(of: scenePhase) { _, newPhase in
          if newPhase == .active {
            if holder.hasFailed {
              reload(player)
            }
            reconcileAutoplay(player, resumesFullscreen: true)
          }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.videoAutoplayStatusDidChangeNotification)) { _ in
          reconcileAutoplay(player)
        }
        .onDisappear {
          isVisible = false
          removeObserver()
          guard !PictureInPicture.shared.isPlaying(player) else { return }
          player.pause()
          player.seek(to: .zero)
        }
        .onChange(of: inLightbox) { _, open in
          guard !open, !PictureInPicture.shared.isPlaying(player) else { return }
          player.volume = 0
          if autoPlayVideos, isVisible {
            player.play()
          } else {
            player.pause()
            player.seek(to: .zero)
          }
        }
        .fullScreenCover(item: $lightbox) { lightbox in
          LightBoxImage(pages: lightbox.pages, i: lightbox.start, doLiveText: Defaults[.BehaviorDefSettings].doLiveText, reveal: lightbox.reveal)
        }
      }
    }
  }

  func reconcileAutoplay(_ player: AVPlayer, resumesFullscreen: Bool = false) {
    let systemEnabled = UIAccessibility.isVideoAutoplayEnabled
    if systemAutoplay != systemEnabled {
      systemAutoplay = systemEnabled
    }
    guard isVisible, !inLightbox, !PictureInPicture.shared.isPlaying(player) else { return }
    if videoDefSettings.autoPlay, systemEnabled {
      if !isFullscreen || resumesFullscreen {
        player.play()
      }
    } else if !isFullscreen {
      player.pause()
    }
  }

  func reload(_ player: AVPlayer) {
    _ = holder.reload {
      guard isVisible else { return }
      observePlayback(player)
      if autoPlayVideos, !inLightbox {
        player.play()
      }
    }
  }

  func observePlayback(_ player: AVPlayer) {
    let center = NotificationCenter.default
    let item = player.currentItem
    let loop = loopVideos
    player.actionAtItemEnd = loop ? .none : .pause
    observerBag.set([
      center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
        if loop {
          player.seek(to: .zero)
        }
      },
      center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { _ in
        reload(player)
      },
      center.addObserver(forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main) { _ in
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
          if player.currentItem === item, player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
            reload(player)
          }
        }
      },
    ])
  }

  func removeObserver() {
    observerBag.removeAll()
  }
}

final class PlayerLayerHostView: UIView {
  override class var layerClass: AnyClass {
    AVPlayerLayer.self
  }

  var playerLayer: AVPlayerLayer {
    layer as! AVPlayerLayer
  }
}

struct InlinePlayerLayer: UIViewRepresentable {
  let player: AVPlayer
  var gravity: AVLayerVideoGravity = .resizeAspectFill

  func makeUIView(context: Context) -> PlayerLayerHostView {
    let view = PlayerLayerHostView()
    view.playerLayer.player = player
    view.playerLayer.videoGravity = gravity
    return view
  }

  func updateUIView(_ view: PlayerLayerHostView, context: Context) {
    if view.playerLayer.player !== player {
      view.playerLayer.player = player
    }
    view.playerLayer.videoGravity = gravity
  }

  static func dismantleUIView(_ view: PlayerLayerHostView, coordinator: ()) {
    view.playerLayer.player = nil
  }
}

final class PictureInPicture {
  static let shared = PictureInPicture()
  private var holder: VideoPlayerHolder?
  private var owner: AnyObject?
  var fullscreenPlayers = 0

  func isPlaying(_ player: AVPlayer?) -> Bool {
    player != nil && holder?.player === player
  }

  func begin(_ holder: VideoPlayerHolder, owner: AnyObject) {
    self.holder = holder
    self.owner = owner
  }

  func end(_ owner: AnyObject) {
    guard self.owner === owner else { return }
    holder?.player?.volume = 0
    holder = nil
    self.owner = nil
    if Defaults[.VideoDefSettings].pauseBGAudioOnFullscreen, fullscreenPlayers == 0 {
      scheduleAudioMixing(true)
    }
  }
}

struct AVPlayerRepresentable: UIViewRepresentable {
  @Binding var fullscreen: Bool
  var autoPlayVideos: Bool
  let player: AVPlayer
  let aspect: AVLayerVideoGravity
  var controller: UIViewController

  func makeUIView(context: Context) -> UIView {
    let view = UIView()
    let playerController = NiceAVPlayer(fullscreen: $fullscreen, autoPlayVideos: autoPlayVideos)
    playerController.allowsVideoFrameAnalysis = false
    playerController.player = player
    playerController.videoGravity = aspect

    context.coordinator.controller = playerController
    controller.addChild(playerController)
    playerController.view.frame = view.bounds
    view.addSubview(playerController.view)
    playerController.didMove(toParent: controller)
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    return view
  }

  func updateUIView(_ view: UIView, context: Context) {
    if let playerController = context.coordinator.controller, playerController.autoPlayVideos != autoPlayVideos {
      playerController.autoPlayVideos = autoPlayVideos
    }
    if fullscreen {
      context.coordinator.controller?.enterFullScreen(animated: true)
    }
  }

  static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
    if let playerController = coordinator.controller {
      playerController.willMove(toParent: nil)
      playerController.view.removeFromSuperview()
      playerController.removeFromParent()
      playerController.player = nil
    }
    coordinator.controller = nil
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  class Coordinator: NSObject {
    var controller: NiceAVPlayer?
  }
}

class NiceAVPlayer: AVPlayerViewController, AVPlayerViewControllerDelegate {
  @Binding var fullscreen: Bool
  var autoPlayVideos: Bool
  var gone = true
  private var loopObserver: NSObjectProtocol?
  @Default(.VideoDefSettings) private var videoDefSettings
  override open var prefersStatusBarHidden: Bool {
    true
  }

  init(fullscreen: Binding<Bool>, autoPlayVideos: Bool) {
    self._fullscreen = fullscreen
    self.autoPlayVideos = autoPlayVideos
    super.init(nibName: nil, bundle: nil)
    self.delegate = self
    showsPlaybackControls = false
  }

  required init?(coder aDecoder: NSCoder) {
    self.autoPlayVideos = false
    self._fullscreen = Binding(get: { true }, set: { _, _ in })
    super.init(coder: aDecoder)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if videoDefSettings.loop, let player = self.player, loopObserver == nil {
      loopObserver = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: player.currentItem,
        queue: nil,
      ) { [weak self] _ in
        guard self != nil else { return }
        player.seek(to: .zero)
        player.play()
      }
    }
    if autoPlayVideos, gone {
      self.player?.play()
      gone = false
    }
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    if let token = loopObserver {
      NotificationCenter.default.removeObserver(token)
      loopObserver = nil
    }
    if !showsPlaybackControls {
      player?.pause()
      gone = true
    }
  }

  deinit {
    if let token = loopObserver {
      NotificationCenter.default.removeObserver(token)
    }
  }

  @objc private func didTapView() {
    enterFullScreen(animated: true)
    showsPlaybackControls = true
  }

  func enterFullScreen(animated: Bool) {
    let selector = NSSelectorFromString("enterFullScreenAnimated:completionHandler:")

    if self.responds(to: selector) {
      self.perform(selector, with: animated, with: nil)
    }
  }

  func playerViewController(
    _ playerViewController: AVPlayerViewController,
    willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator,
  ) {
    coordinator.animate(alongsideTransition: nil) { [weak self] context in
      guard let self else { return }
      if context.isCancelled {
      } else {
        self.player?.volume = 1.0
        self.player?.play()
        self.showsPlaybackControls = true
      }
    }
  }

  func playerViewController(
    _ playerViewController: AVPlayerViewController,
    willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator,
  ) {
    let isPlaying = self.player?.isPlaying ?? false
    coordinator.animate(alongsideTransition: nil) { [weak self] context in
      guard let self else { return }
      if context.isCancelled {
      } else {
        self.fullscreen = false
        doThisAfter(0.0) {
          self.player?.volume = 0.0
        }
        self.showsPlaybackControls = false
        if !self.autoPlayVideos {
          self.player?.pause()
        } else if isPlaying {
          self.player?.play()
        }
      }
    }
  }
}

extension AVPlayer {}
