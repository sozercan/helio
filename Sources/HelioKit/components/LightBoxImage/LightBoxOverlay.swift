//
//  LightBoxOverlay.swift
//  Helio
//
//  Created by Igor Marcossi on 07/08/23.
//

import Defaults
import NukeUI
import SwiftUI

struct LightBoxOverlay: View {
  let postTitle: String
  let badgeKit: BadgeKit
  let avatarImageRequest: ImageRequest?
  var opacity: CGFloat
  /// The safe area the media runs under. The title and buttons keep clear of its sides.
  var safeArea = EdgeInsets()
  /// The image showing, to save or share. Nil for a video.
  var img: ImgExtracted?
  /// The video showing, for its playback buttons.
  var video: LightBoxVideo?
  /// The page's place among its post's images.
  var index: Int
  var count: Int
  /// A GIF's or video's progress bar, above the buttons.
  var scrubber: (any MediaScrubbable)?
  @Binding var loading: Bool
  @Environment(\.dismiss) var dismiss
  @Binding var done: Bool
  @Environment(\.useTheme) private var selectedTheme
  @State private var isPresentingShareSheet = false
  @State private var sharedImageData: Data?
  var body: some View {
    VStack(alignment: .leading) {
      VStack(alignment: .leading, spacing: 8) {
        Text(postTitle)
          .fontSize(20, .semibold)
          .allowsHitTesting(false)
        BadgeView(avatarRequest: avatarImageRequest, saved: false, usernameColor: nil, author: badgeKit.author, userFlair: badgeKit.userFlair, created: badgeKit.created, avatarURL: nil, theme: selectedTheme.postLinks.theme.badge)
      }
      // Clear of the Close button at the top trailing corner.
      .padding(.trailing, 56)

      Spacer()

      if count > 1 {
        Text("\(index + 1)/\(count)")
          .fontSize(16, .semibold)
          .accessibilityLabel("Image \(index + 1) of \(count)")
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(Capsule(style: .continuous).fill(.regularMaterial))
          .frame(maxWidth: .infinity)
          .allowsHitTesting(false)
      }

      if let scrubber {
        MediaProgressBar(scrubber: scrubber)
          .padding(.horizontal, 12)
          .padding(.bottom, 8)
      }

      HStack(spacing: 12) {
        // MANDRAKE
//           if let post {
//               LightBoxButton(icon: "bubble.right") {
//             if let data = post.data {
//                   Nav.to(.reddit(.post(Post(id: post.id, subID: data.subreddit))))
//                   dismiss()
//                 }
//               }
//           }

        if let video {
          // A video that failed offers to try again instead.
          if !video.failed {
            LightBoxVideoButtons(video: video)
          }
        } else if let img {
          LightBoxButton(icon: "square.and.arrow.down", label: "Save Image") {
            withAnimation(spring) {
              loading = true
            }
            saveMedia(img.url.absoluteString, .image) { _ in
              withAnimation(spring) {
                done = true
              }
            }
          }
          LightBoxButton(icon: "square.and.arrow.up", label: "Share Image") {
            Task {
              sharedImageData = try await downloadAndSaveImage(url: img.url)
            }
            isPresentingShareSheet.toggle()
          }
          .contentShape(Circle())
          .sheet(isPresented: $isPresentingShareSheet) {
            if let sharedImageData, let uiimg = UIImage(data: sharedImageData) {
              let image = ShareImage(placeholderItem: uiimg)
              ShareSheet(items: [image])
            }
          }
        }
      }
      .compositingGroup()
      .frame(maxWidth: .infinity)
    }
    .multilineTextAlignment(.leading)
    .foregroundColor(.white)
    .padding(.leading, safeArea.leading)
    .padding(.trailing, safeArea.trailing)
    .padding(.horizontal, 12)
    .padding(.bottom, 32)
    .padding(.top, 64)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(
      VStack(spacing: 0) {
        Rectangle()
          .fill(LinearGradient(
            gradient: Gradient(stops: [
              .init(color: Color.black.opacity(1), location: 0),
              .init(color: Color.black.opacity(0), location: 1),
            ]),
            startPoint: .top,
            endPoint: .bottom,
          ))
          .frame(height: 150)
        Spacer()
        Rectangle()
          .fill(LinearGradient(
            gradient: Gradient(stops: [
              .init(color: Color.black.opacity(1), location: 0),
              .init(color: Color.black.opacity(0), location: 1),
            ]),
            startPoint: .bottom,
            endPoint: .top,
          ))
          .frame(height: 150)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .allowsHitTesting(false),
    )
    .compositingGroup()
    .opacity(opacity)
    .allowsHitTesting(opacity != 0)
  }
}

/// A video's play, sound and Picture in Picture buttons.
private struct LightBoxVideoButtons: View {
  let video: LightBoxVideo

  var body: some View {
    LightBoxButton(icon: video.isPlaying ? "pause.fill" : "play.fill", label: video.isPlaying ? "Pause" : "Play") {
      video.togglePlayback()
    }
    LightBoxButton(icon: video.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", label: video.isMuted ? "Unmute" : "Mute") {
      video.isMuted.toggle()
    }
    if video.canPictureInPicture {
      LightBoxButton(icon: "pip.enter", label: "Picture in Picture") {
        video.startPictureInPicture()
      }
    }
  }
}
