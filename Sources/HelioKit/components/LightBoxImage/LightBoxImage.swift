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
  var postTitle: String?
  var badgeKit: BadgeKit?
  var avatarImageRequest: ImageRequest?
  var markAsSeen: (() async -> Void)?
  var i: Int
  var imagesArr: [ImgExtracted]
  var doLiveText: Bool
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

  private enum Axis {
    case horizontal
    case vertical
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

  /// Shows image `index`, for VoiceOver, which can't drag between them.
  func page(to index: Int) {
    let index = min(imagesArr.count - 1, max(0, index))
    guard index != activeIndex else { return }
    activeIndex = index
    withAnimation(motionAware(spring)) {
      xPos = -(CGFloat(index) * (.screenW + SPACING))
    }
  }

  var body: some View {
    let interpolate = interpolatorBuilder([0, 100], value: abs(drag.height))
    HStack(spacing: SPACING) {
      ForEach(Array(imagesArr.enumerated()), id: \.element.id) { index, img in
        let selected = index == activeIndex
        LightBoxElementView(el: img, label: postTitle, onTap: toggleOverlay, doLiveText: doLiveText, showOverlay: showOverlay, isPinching: $isPinching, isZoomed: $isZoomed)
          .allowsHitTesting(selected)
          .accessibilityHidden(!selected)
          .modifier(LightBoxPaging(pages: imagesArr.count, page: { page(to: activeIndex + $0) }))
          .scaleEffect(!selected ? 1 : interpolate([1, 0.9], true))
          .blur(radius: selected && loading ? 24 : 0)
          .offset(x: !selected ? 0 : dragAxis == .vertical ? drag.width : 0, y: i != activeIndex ? 0 : dragAxis == .vertical ? drag.height : 0)
      }
    }
    .fixedSize(horizontal: true, vertical: false)
    .offset(x: xPos + (dragAxis == .horizontal ? drag.width : 0))
    .frame(maxWidth: .screenW, maxHeight: .screenH, alignment: .leading)
    .highPriorityGesture(
      scale > 1
        ? nil
        : DragGesture(minimumDistance: 20)
        .onChanged { val in
          if dragAxis == nil || dragOffset == nil {
            dragOffset = val.translation
            if abs(val.predictedEndTranslation.width) > abs(val.predictedEndTranslation.height) {
              dragAxis = .horizontal
            } else if abs(val.predictedEndTranslation.width) < abs(val.predictedEndTranslation.height) {
              dragAxis = .vertical
            }
          }

          if let dragAxis, let dragOffset {
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
          if dragAxis == .horizontal {
            let predictedEnd = val.predictedEndTranslation.width - (dragOffset?.width ?? 0)
            drag = .zero
            xPos += val.translation.width - (dragOffset?.width ?? 0)
            dragOffset = nil
            let newActiveIndex = min(imagesArr.count - 1, max(0, activeIndex + (predictedEnd < -(.screenW / 2) ? 1 : predictedEnd > .screenW / 2 ? -1 : 0)))
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
    .overlay {
      if let postTitle, let badgeKit {
        LightBoxOverlay(postTitle: postTitle, badgeKit: badgeKit, avatarImageRequest: avatarImageRequest, opacity: !showOverlay || isPinching ? 0 : interpolate([1, 0], false), imagesArr: imagesArr, activeIndex: activeIndex, loading: $loading, done: $done)
      }
    }
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
      Button("Close", systemImage: "xmark", action: close)
        .labelStyle(.iconOnly)
        .fontSize(17, .semibold)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
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
      drag = .zero
      dragOffset = nil
      dragAxis = nil
      xPos = -CGFloat(activeIndex) * (.screenW + SPACING)
    }
    .onAppear {
      if let markAsSeen {
        Task(priority: .background) { await markAsSeen() }
      }
      xPos = -CGFloat(i) * (.screenW + SPACING)
      activeIndex = i
      doThisAfter(0.0) {
        withAnimation(.easeOut) {
          appearContent = true
          appearBlack = true
        }
      }
    }
    .transition(.opacity)
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
