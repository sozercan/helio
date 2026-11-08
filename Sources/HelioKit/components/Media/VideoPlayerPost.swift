import AVFoundation
import AVKit
import Combine
import CoreMedia
import Defaults
import SwiftUI

/// Owns ONE AVPlayer for the lifetime of a single VideoPlayerPost view. Held via @StateObject, so its
/// `deinit` fires reliably when SwiftUI destroys the cell (de-realizes it from the List) — unlike
/// `onDisappear`, which a List fires unreliably. This is the fix for the real bug: previously each
/// SharedVideo stored its own AVPlayer and PostHelioData's append-only feed-entity list pinned it
/// alive forever, so players NEVER deallocated (52 after one feed load, climbing for the whole
/// session) until iOS silently stopped letting new players start and videos froze until a restart.
/// Tying the player to the view's lifetime caps the live count to the List's realization window and
/// guarantees teardown.
final class VideoPlayerHolder: ObservableObject {
  let player: AVPlayer?
  /// False until the current item can play; the cell shows the post's preview image until then.
  @Published private(set) var isReadyToPlay = false
  /// The current item failed to load. Failing to become playable posts no notification, so
  /// the view watches this to retry.
  @Published private(set) var itemFailed = false
  private let url: URL?
  private var statusObservation: NSKeyValueObservation?
  private var reloads = 0
  private let maxReloads = 2

  init(url: URL?) {
    self.url = url
    if let url {
      let p = AVPlayer(playerItem: AVPlayerItem(url: url))
      p.volume = 0.0
      player = p
    } else {
      player = nil
    }
    observeCurrentItem()
  }

  /// Swaps in a fresh item for a failed or stuck one. Returns false once retries are used up.
  @discardableResult
  func reload() -> Bool {
    guard let player, let url, reloads < maxReloads else { return false }
    reloads += 1
    isReadyToPlay = false
    itemFailed = false
    player.replaceCurrentItem(with: AVPlayerItem(url: url))
    observeCurrentItem()
    return true
  }

  /// Tries again once retries ran out, when the user asks.
  func retry() {
    reloads = 0
    reload()
  }

  var hasFailed: Bool {
    player?.status == .failed || player?.currentItem?.status == .failed
  }

  private func observeCurrentItem() {
    statusObservation = player?.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
      let ready = item.status == .readyToPlay
      let failed = item.status == .failed
      DispatchQueue.main.async {
        self?.isReadyToPlay = ready
        self?.itemFailed = failed
      }
    }
  }

  deinit {
    statusObservation?.invalidate()
    player?.pause()
    player?.replaceCurrentItem(with: nil)
  }
}

struct SharedVideo: Equatable {
  static func == (lhs: SharedVideo, rhs: SharedVideo) -> Bool {
    lhs.url == rhs.url && lhs.size == rhs.size
  }

  var url: URL
  var size: CGSize
  var posterURL: URL?

  static func get(url: URL, size: CGSize, posterURL: URL? = nil) -> SharedVideo {
    SharedVideo(url: url, size: size, posterURL: posterURL)
  }

  init(url: URL, size: CGSize, posterURL: URL? = nil) {
    self.url = url
    self.size = size
    self.posterURL = posterURL
  }
}

/// Holds block-based NotificationCenter tokens for a video and removes them on teardown.
/// Block observers can ONLY be removed with the token returned at registration, and this
/// bag's deinit guarantees removal even if SwiftUI recycles a cell without calling onDisappear.
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
    // The size inputs too: a rotation or column resize only changes `contentWidth`.
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
  /// The post, as the lightbox shows it over the video.
  var lightboxPost: LightBoxPost
  /// The post's data, by which the lightbox finds it among the feed's posts, to go on to the
  /// media of the posts around it. Nil on a post's page.
  var feedPost: PostHelioData?
  /// The native fullscreen of the player shown with a `controller`.
  @State private var fullscreen = false
  /// The lightbox, when there's no window's to open it in.
  @State private var lightbox: LightBoxTimeline?
  @Environment(\.feedPostsSource) private var feed
  @Environment(\.lightBoxPresenter) private var presenter

  /// The lightbox shows this video, playing it in this row's player.
  private var inLightbox: Bool {
    lightbox != nil || presenter?.isShowing(holder) == true
  }

  @Default(.VideoDefSettings) private var videoDefSettings
  @Environment(\.scenePhase) private var scenePhase
  @State private var observerBag = VideoObserverBag()
  @State private var isVisible = false
  /// iOS's Auto-Play Video Previews setting, kept as state so changing it redraws the player.
  @State private var systemAutoplay = UIAccessibility.isVideoAutoplayEnabled
  @StateObject private var holder: VideoPlayerHolder

  /// Off when iOS's Auto-Play Video Previews setting is, too.
  private var autoPlayVideos: Bool {
    videoDefSettings.autoPlay && systemAutoplay
  }

  private var loopVideos: Bool {
    videoDefSettings.loop
  }

  /// Open in the lightbox, or the native fullscreen of the player shown with a `controller`.
  private var isFullscreen: Bool {
    fullscreen || inLightbox
  }

  /// Opens the lightbox on the video, playing on from where its preview is.
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
    _holder = StateObject(wrappedValue: VideoPlayerHolder(url: cachedVideo != nil ? url : nil))
  }

  var body: some View {
    let maxHeight: CGFloat = (maxMediaHeightScreenPercentage / 100) * .screenH
    // Square until Reddit gives us real dimensions, matching getPostDimensions.
    let knownSize = size.width > 0 && size.height > 0
    let sourceWidth = knownSize ? size.width : contentWidth
    let sourceHeight = knownSize ? size.height : contentWidth
    let propHeight = (contentWidth * sourceHeight) / sourceWidth
    let finalHeight = maxMediaHeightScreenPercentage != 110 ? Double(min(maxHeight, propHeight)) : Double(propHeight)

    if let sharedVideo, let player = holder.player {
      // (player comes from the per-view holder, bound in the if-let above)
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
            // Only attach a player layer (= a decode pipeline) when this cell is actually
            // on-screen and not in fullscreen. Off-screen cells render Color.clear, which
            // tears the layer down via InlinePlayerLayer.dismantleUIView and frees the pipeline.
            if isVisible, !inLightbox {
              InlinePlayerLayer(player: player)
            } else {
              Color.clear
            }
          }
          .frame(width: compact ? scaledCompactModeThumbSize() : contentWidth, height: compact ? scaledCompactModeThumbSize() : CGFloat(finalHeight))
          .accessibilityIgnoresInvertColors()
          .overlay {
            // Covers the player's black frame while the video buffers.
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
            // The setting may have changed while the app was in the background. As before,
            // coming back resumes a fullscreen video too.
            reconcileAutoplay(player, resumesFullscreen: true)
          }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.videoAutoplayStatusDidChangeNotification)) { _ in
          reconcileAutoplay(player)
        }
        .onDisappear {
          isVisible = false
          removeObserver()
          // Synchronous on purpose: a deferred pause could land after the cell reappeared and
          // leave its video stopped at 0:00.
          guard !PictureInPicture.shared.isPlaying(player) else { return }
          player.pause()
          player.seek(to: .zero)
        }
        // The lightbox plays the video while it shows it (`LightBoxVideo`). Back from it, the
        // preview goes on muted, or stops at its start without autoplay.
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
          LightBoxImage(pages: lightbox.pages, i: lightbox.start, doLiveText: Defaults[.BehaviorDefSettings].doLiveText)
        }
      }
    }
  }

  /// Plays the inline preview when autoplay is on, and pauses it when Auto-Play Video Previews
  /// was turned off. Leaves fullscreen and picture-in-picture playback, which the user controls,
  /// alone, unless `resumesFullscreen` (coming back to the app resumes it, as it always has).
  func reconcileAutoplay(_ player: AVPlayer, resumesFullscreen: Bool = false) {
    let systemEnabled = UIAccessibility.isVideoAutoplayEnabled
    if systemAutoplay != systemEnabled {
      systemAutoplay = systemEnabled
    }
    // The lightbox plays its videos itself, this one included.
    guard isVisible, !inLightbox, !PictureInPicture.shared.isPlaying(player) else { return }
    if videoDefSettings.autoPlay, systemEnabled {
      // A setting change doesn't restart a fullscreen video the user paused.
      if !isFullscreen || resumesFullscreen {
        player.play()
      }
    } else if !isFullscreen {
      player.pause()
    }
  }

  /// Swaps in a fresh item and re-attaches the observers, which are tied to the old one.
  func reload(_ player: AVPlayer) {
    guard holder.reload() else { return }
    observePlayback(player)
    if autoPlayVideos, isVisible {
      player.play()
    }
  }

  func observePlayback(_ player: AVPlayer) {
    let center = NotificationCenter.default
    let item = player.currentItem
    let loop = loopVideos
    // With .none the player keeps rolling at the end, so seeking back loops without a pause.
    player.actionAtItemEnd = loop ? .none : .pause
    // Store the tokens so they can actually be removed; the bag's deinit is the safety net.
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
        // Stalls usually recover once the buffer refills; only reload if it's still stuck.
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

/// A bare AVPlayerLayer-backed view for inline (non-fullscreen) feed/detail video.
/// SwiftUI's `VideoPlayer` gave no teardown hook, so its decode pipeline (one per AVPlayerLayer)
/// leaked for every realized cell until iOS's ~16-pipeline limit was hit. This owns the layer
/// explicitly and releases it in `dismantleUIView`; combined with the `isVisible` gate in
/// VideoPlayerPost, the number of live decode pipelines stays near the on-screen video count.
/// The shared cached AVPlayer is left intact for instant resume.
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

/// Keeps a video's player, and what plays it in Picture in Picture, alive while it floats, since
/// the lightbox that started it has closed and the feed row it came from can go too.
final class PictureInPicture {
  static let shared = PictureInPicture()
  private var holder: VideoPlayerHolder?
  private var owner: AnyObject?
  /// Lightbox videos playing, which own the audio session while they're up.
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
    // Back to the feed's muted inline playback.
    holder?.player?.volume = 0
    holder = nil
    self.owner = nil
    // Fullscreen paused other apps' audio, and leaving it for PiP skipped resuming it.
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

  /// Without this, every video cell scrolled past leaks its AVPlayerViewController:
  /// `makeUIView` calls `controller.addChild(...)` but nothing ever calls
  /// `removeFromParent()`, so the child VC (and its AVPlayerLayer / decode session)
  /// stays alive on the long-lived feed controller. iOS only allows ~16 simultaneous
  /// video pipelines, so after scrolling past enough videos new ones can't render
  /// (no autoplay in the list, a frame or two then a stall in the post). Detaching
  /// here releases the layer's decode session while leaving the shared cached
  /// AVPlayer intact for reuse.
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
    // Block observers need the token to be removed; removeObserver(self,…) removed nothing.
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
        // Still embedded inline
      } else {
        // Presented full screen
        // Take strong reference to playerViewController if needed
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
        // Still full screen
      } else {
        // Embedded inline
        // Remove strong reference to playerViewController if held
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
