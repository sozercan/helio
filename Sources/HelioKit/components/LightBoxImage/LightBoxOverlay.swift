import Defaults
import NukeUI
import SwiftUI

struct LightBoxOverlay: View {
  let postTitle: String
  let badgeKit: BadgeKit
  let avatarImageRequest: ImageRequest?
  var opacity: CGFloat
  var safeArea = EdgeInsets()
  var img: ImgExtracted?
  var video: LightBoxVideo?
  var index: Int
  var count: Int
  var scrubber: (any MediaScrubbable)?
  @Binding var loading: Bool
  @Environment(\.dismiss) var dismiss
  @Binding var done: Bool
  @Environment(\.useTheme) private var selectedTheme
  @State private var shareTask: Task<Void, Never>?
  var body: some View {
    VStack(alignment: .leading) {
      VStack(alignment: .leading, spacing: 8) {
        Text(postTitle)
          .fontSize(20, .semibold)
          .allowsHitTesting(false)
        BadgeView(avatarRequest: avatarImageRequest, saved: false, usernameColor: nil, author: badgeKit.author, userFlair: badgeKit.userFlair, created: badgeKit.created, avatarURL: nil, theme: selectedTheme.postLinks.theme.badge)
      }
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
        if let video {
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
            shareTask?.cancel()
            shareTask = Task {
              guard let data = try? await downloadAndSaveImage(url: img.url), !Task.isCancelled, let uiimg = UIImage(data: data) else { return }
              ShareUtils.shareImage(uiimg)
            }
          }
          .contentShape(Circle())
          .onDisappear { shareTask?.cancel() }
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
