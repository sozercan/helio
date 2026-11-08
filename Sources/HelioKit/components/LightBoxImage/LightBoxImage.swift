//
//  LightBoxImage.swift
//  Helio
//
//  Created by Igor Marcossi on 28/06/23.
//

import Defaults
import NukeUI
import SwiftUI

private let SPACING = 24.0

struct LightBoxImage: View {
  var pages: [LightBoxPage]
  var i: Int
  var doLiveText: Bool
  /// Scrolls the feed behind to the post showing.
  var reveal: ((String) -> Void)?
  /// The feed post last scrolled to, the one opened to begin with.
  @State private var revealedFeedID: String?
  @Environment(\.dismiss) private var dismiss
  @State private var appearBlack = false
  @State private var appearContent = false
  @State private var dragOffset: CGSize?
  @State private var drag: CGSize = .zero
  @State private var xPos: CGFloat = 0
  @State private var dragAxis: Axis?
  @State private var activeIndex = 0
  @State private var loading = false
  @State private var done = false
  @State private var showOverlay = true
  @State private var isPinching: Bool = false
  @State private var isZoomed: Bool = false
  @State private var scale: CGFloat = 1.0
  /// The pages' GIF scrubbers and video players.
  @State private var media: LightBoxMediaStore
  /// The page a held drag is scrubbing.
  @State private var scrubIndex: Int?
  /// The posts already marked read since it opened.
  @State private var seenPosts: Set<String> = []
  /// Resets when the drag ends or is cancelled; a cancelled drag skips `onEnded`.
  @GestureState private var dragging = false

  init(pages: [LightBoxPage], i: Int, doLiveText: Bool, reveal: ((String) -> Void)? = nil) {
    self.pages = pages
    self.i = i
    self.doLiveText = doLiveText
    self.reveal = reveal
    _revealedFeedID = State(initialValue: pages.indices.contains(i) ? pages[i].post.feedID : nil)
    _media = State(initialValue: LightBoxMediaStore(pages: pages))
    _activeIndex = State(initialValue: i)
  }

  /// One post's images.
  init(postTitle: String? = nil, badgeKit: BadgeKit? = nil, avatarImageRequest: ImageRequest? = nil, markAsSeen: (() async -> Void)? = nil, i: Int, imagesArr: [ImgExtracted], doLiveText: Bool) {
    let post = LightBoxPost(key: "", title: postTitle, badgeKit: badgeKit, avatarImageRequest: avatarImageRequest, markAsSeen: markAsSeen)
    self.init(pages: post.pages(imagesArr), i: i, doLiveText: doLiveText)
  }

  private enum Axis {
    case horizontal
    case vertical
    /// A held drag on a GIF or video, which the hold scrubs: the drag stands aside.
    case scrub
  }

  /// A finger held on a GIF or video scrubs it as it moves, with the progress bar showing.
  private func hold(_ event: LightBoxScrub) {
    switch event {
    case .began:
      // The page's own zoom was checked where the hold began (`LightBoxGestures`): `isZoomed` is
      // shared by the pages, and can be left set by one VoiceOver paged away from.
      guard let scrubber = media.scrubber(at: activeIndex), scrubber.begin() else { return }
      scrubIndex = activeIndex
      if !showOverlay {
        toggleOverlay()
      }
    case let .moved(translation):
      if let scrubIndex {
        media.scrubber(at: scrubIndex)?.update(translation: translation, width: .screenW)
      }
    case .ended:
      endScrub()
    }
  }

  /// Marks the post of the page showing read, once.
  private func markSeen(_ index: Int) {
    guard pages.indices.contains(index) else { return }
    let page = pages[index]
    guard let markAsSeen = page.post.markAsSeen, seenPosts.insert(page.post.key).inserted else { return }
    Task(priority: .background) { await markAsSeen() }
  }

  private func endScrub() {
    if let scrubIndex {
      media.scrubber(at: scrubIndex)?.end()
    }
    scrubIndex = nil
    if dragAxis == .scrub {
      dragOffset = nil
      dragAxis = nil
    }
  }

  func toggleOverlay() {
    withAnimation(.easeOut(duration: 0.2)) {
      showOverlay.toggle()
    }
  }

  func close() {
    withAnimation(.easeOut) {
      appearBlack = false
    }
    dismiss()
  }

  /// Shows image `index`, for VoiceOver, which can't drag between them, and trackpad swipes.
  func page(to index: Int) {
    let index = min(pages.count - 1, max(0, index))
    guard index != activeIndex else { return }
    activeIndex = index
    withAnimation(motionAware(spring)) {
      xPos = -(CGFloat(index) * (.screenW + SPACING))
    }
  }

  /// The image or video of page `index`.
  @ViewBuilder
  private func pageContent(_ index: Int, _ page: LightBoxPage) -> some View {
    let onSwipe: ((Int) -> Void)? = pages.count > 1 ? { self.page(to: index + $0) } : nil
    switch page.media {
    case let .image(img):
      LightBoxElementView(el: img, label: page.post.title, onTap: toggleOverlay, onSwipe: onSwipe, onHold: img.url.isGIF ? hold : nil, doLiveText: doLiveText, showOverlay: showOverlay, gifScrubber: img.url.isGIF ? media.gif(index) : nil, isPinching: $isPinching, isZoomed: $isZoomed)
    case let .video(video, _):
      if let player = media.video(index, onPictureInPictureStart: close) {
        LightBoxVideoPage(video: player, holder: player.holder, posterURL: video.posterURL, label: page.post.title, selected: index == activeIndex, onTap: toggleOverlay, onSwipe: onSwipe, onHold: hold)
      }
    }
  }

  /// Page `index`. Only the pages beside the one showing load their media: a feed's can be hundreds.
  @ViewBuilder
  private func pageView(_ index: Int, selectedScale: CGFloat) -> some View {
    let selected = index == activeIndex
    let page = pages[index]
    if abs(index - activeIndex) <= 1 {
      pageContent(index, page)
        .allowsHitTesting(selected)
        .accessibilityHidden(!selected)
        // The page, which changes as VoiceOver users swipe through the gallery.
        .accessibilityValue(page.count > 1 ? "\(page.index + 1) of \(page.count)" : "")
        .modifier(LightBoxPaging(pages: pages.count, page: { self.page(to: activeIndex + $0) }))
        .scaleEffect(!selected ? 1 : selectedScale)
        .blur(radius: selected && loading ? 24 : 0)
        .offset(x: !selected ? 0 : dragAxis == .vertical ? drag.width : 0, y: !selected ? 0 : dragAxis == .vertical ? drag.height : 0)
    } else {
      Color.clear
        .frame(width: .screenW)
        .accessibilityHidden(true)
    }
  }

  /// The post's title and author, and the image's buttons.
  @ViewBuilder
  private func infoOverlay(opacity: CGFloat) -> some View {
    if pages.indices.contains(activeIndex), let postTitle = pages[activeIndex].post.title, let badgeKit = pages[activeIndex].post.badgeKit {
      let page = pages[activeIndex]
      LightBoxOverlay(postTitle: postTitle, badgeKit: badgeKit, avatarImageRequest: page.post.avatarImageRequest, opacity: opacity, img: page.media.image, video: media.video(activeIndex, onPictureInPictureStart: close), index: page.index, count: page.count, scrubber: media.scrubber(at: activeIndex), loading: $loading, done: $done)
    }
  }

  var body: some View {
    lightbox
      .onChange(of: activeIndex) { _, index in
        markSeen(index)
        media.show(index)
        if let feedID = pages[index].post.feedID, feedID != revealedFeedID {
          revealedFeedID = feedID
          reveal?(feedID)
        }
      }
      .onAppear { media.show(activeIndex) }
      .onDisappear { media.releaseAll() }
  }

  @ViewBuilder
  private var lightbox: some View {
    let interpolate = interpolatorBuilder([0, 100], value: abs(drag.height))
    let selectedScale = interpolate([1, 0.9], true)
    HStack(spacing: SPACING) {
      // By position: a feed can hold the same image twice.
      ForEach(pages.indices, id: \.self) { index in
        pageView(index, selectedScale: selectedScale)
      }
    }
    .fixedSize(horizontal: true, vertical: false)
    .offset(x: xPos + (dragAxis == .horizontal ? drag.width : 0))
    .frame(maxWidth: .screenW, maxHeight: .screenH, alignment: .leading)
    .highPriorityGesture(
      scale > 1
        ? nil
        : DragGesture(minimumDistance: 20)
        .updating($dragging) { _, dragging, _ in dragging = true }
        .onChanged { val in
          if dragAxis == nil || dragOffset == nil {
            dragOffset = val.translation
            if scrubIndex != nil {
              dragAxis = .scrub
            } else if abs(val.predictedEndTranslation.width) > abs(val.predictedEndTranslation.height) {
              dragAxis = .horizontal
            } else if abs(val.predictedEndTranslation.width) < abs(val.predictedEndTranslation.height) {
              dragAxis = .vertical
            }
          }

          if dragAxis == .scrub {
            return
          } else if let dragAxis, let dragOffset {
            var transaction = Transaction()
            transaction.isContinuous = true
            transaction.animation = .interpolatingSpring(stiffness: 1000, damping: 100, initialVelocity: 0)

            var endPos = val.translation
            if dragAxis == .horizontal {
              endPos.height = 0
            }
            withTransaction(transaction) {
              drag = endPos - dragOffset
            }
          }
        }
        .onEnded { val in
          if dragAxis == .scrub {
            dragOffset = nil
            dragAxis = nil
          } else if dragAxis == .horizontal {
            let predictedEnd = val.predictedEndTranslation.width - (dragOffset?.width ?? 0)
            drag = .zero
            xPos += val.translation.width - (dragOffset?.width ?? 0)
            dragOffset = nil
            // Half a phone's width: half an iPad's or a Mac window's took a long drag.
            let threshold = min(CGFloat.screenW / 2, 200)
            let newActiveIndex = min(pages.count - 1, max(0, activeIndex + (predictedEnd < -threshold ? 1 : predictedEnd > threshold ? -1 : 0)))
            let finalXPos = -(CGFloat(newActiveIndex) * (.screenW + SPACING))
            let distance = abs(finalXPos - xPos)
            activeIndex = newActiveIndex
            var initialVel = abs(predictedEnd / distance)
            initialVel = initialVel < 3.75 ? 0 : initialVel * 2
            withAnimation(motionAware(.interpolatingSpring(stiffness: 150, damping: 17, initialVelocity: initialVel))) {
              xPos = finalXPos
              dragAxis = nil
            }
          } else {
            let shouldClose = abs(val.translation.width) > 100 || abs(val.translation.height) > 100

            if shouldClose {
              withAnimation(.easeOut) {
                appearBlack = false
              }
            }
            withAnimation(motionAware(.interpolatingSpring(stiffness: 200, damping: 20, initialVelocity: 0))) {
              drag = .zero
              dragAxis = nil
              if shouldClose {
                dismiss()
              }
            }
          }
        },
    )
    // Stands the drag down when it ended without `onEnded`, a held drag having taken over.
    .onChange(of: dragging) { _, dragging in
      guard !dragging, dragAxis == .scrub else { return }
      dragOffset = nil
      dragAxis = nil
    }
    .overlay { infoOverlay(opacity: !showOverlay || isPinching ? 0 : interpolate([1, 0], false)) }
    // Taps on the image show or hide the controls; Close, Escape or a swipe closes it.
    .background(
      !appearBlack
        ? nil
        : Color.black
        .opacity(interpolate([1, 0], false))
        .allowsHitTesting(false)
        .transition(.opacity),
    )
    .overlay {
      if loading || done {
        ZStack {
          if done {
            Image(systemName: "checkmark.circle.fill")
              .fontSize(40)
              .transition(.scaleAndBlur)
          } else {
            ProgressView()
              .transition(.scaleAndBlur)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.25))
      }
    }
    .ignoresSafeArea(edges: .all)
    .overlay(alignment: .topTrailing) {
      let chromeOpacity = !showOverlay || isPinching ? 0 : interpolate([1, 0], false)
      Button(action: close) {
        // The label fills the circle, so the whole of it takes the tap: with the plain style,
        // only the label does.
        Label("Close", systemImage: "xmark")
          .labelStyle(.iconOnly)
          .fontSize(17, .semibold)
          .frame(width: 44, height: 44)
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(.white)
      .glassEffect(.regular.interactive(), in: Circle())
      .keyboardShortcut(.cancelAction)
      .padding(.horizontal, 16)
      .padding(.top, 8)
      .opacity(chromeOpacity)
      .allowsHitTesting(chromeOpacity != 0)
    }
    .compositingGroup()
    .opacity(appearContent ? 1 : 0)
    // VoiceOver's scrub gesture closes it, since it can't drag it away.
    .accessibilityAction(.escape) { close() }
    .onChange(of: done) { val in
      if val {
        doThisAfter(0.5) {
          withAnimation(spring) {
            done = false
            loading = false
          }
        }
      }
    }
    // Pages are a window wide, so a resize moves them: keep the current one in view.
    .onChange(of: CGFloat.screenW) {
      endScrub()
      drag = .zero
      dragOffset = nil
      dragAxis = nil
      xPos = -CGFloat(activeIndex) * (.screenW + SPACING)
    }
    .onAppear {
      xPos = -CGFloat(i) * (.screenW + SPACING)
      markSeen(i)
      doThisAfter(0.0) {
        withAnimation(.easeOut) {
          appearContent = true
          appearBlack = true
        }
      }
    }
    // It covers the post: the menu bar's Post commands mustn't move off it underneath.
    .commandTarget(CommandTargets.Target(kind: .modal))
    .transition(.opacity)
  }
}

/// The pages' GIF scrubbers and video players, made as their pages come near and dropped as they
/// go, so a lightbox paging through a feed holds a few at most.
@MainActor
final class LightBoxMediaStore {
  private let pages: [LightBoxPage]
  private var gifs: [Int: GIFScrubber] = [:]
  private var videos: [Int: LightBoxVideo] = [:]
  /// The page showing, whose video plays.
  private var shown: Int?

  init(pages: [LightBoxPage]) {
    self.pages = pages
  }

  func gif(_ index: Int) -> GIFScrubber {
    if let gif = gifs[index] {
      return gif
    }
    let gif = GIFScrubber()
    gifs[index] = gif
    return gif
  }

  /// The player of page `index`, when it's a video.
  func video(_ index: Int, onPictureInPictureStart: (() -> Void)? = nil) -> LightBoxVideo? {
    guard pages.indices.contains(index), case let .video(video, holder) = pages[index].media else { return nil }
    let player = videos[index] ?? LightBoxVideo(video: video, holder: holder)
    videos[index] = player
    if let onPictureInPictureStart {
      player.onPictureInPictureStart = onPictureInPictureStart
    }
    return player
  }

  /// What a held drag on page `index` scrubs: its GIF or video.
  func scrubber(at index: Int) -> (any MediaScrubbable)? {
    guard pages.indices.contains(index) else { return nil }
    switch pages[index].media {
    case let .image(img): return img.url.isGIF ? gif(index) : nil
    case .video: return video(index)
    }
  }

  /// Page `index` shows: plays its video, stops the one before, and drops the far ones.
  func show(_ index: Int) {
    if shown != index {
      // The new one first, so the audio session isn't let go of between two videos.
      video(index)?.activate()
      if let shown {
        videos[shown]?.deactivate()
      }
      shown = index
    }
    for (other, player) in videos where abs(other - index) > 1 {
      player.release()
      videos[other] = nil
    }
    for other in gifs.keys where abs(other - index) > 1 {
      gifs[other] = nil
    }
  }

  /// The lightbox closed.
  func releaseAll() {
    videos.values.forEach { $0.release() }
    videos = [:]
    shown = nil
  }
}

/// Swiping up or down with VoiceOver on a gallery's image shows the next or previous one.
private struct LightBoxPaging: ViewModifier {
  var pages: Int
  /// Moves by the given number of pages.
  var page: (Int) -> Void

  func body(content: Content) -> some View {
    if pages > 1 {
      content.accessibilityAdjustableAction { direction in
        switch direction {
        case .increment: page(1)
        case .decrement: page(-1)
        @unknown default: break
        }
      }
    } else {
      content
    }
  }
}
