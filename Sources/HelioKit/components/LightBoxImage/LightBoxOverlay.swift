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
  var img: ImgExtracted
  /// The image's place among its post's images.
  var index: Int
  var count: Int
  /// A lone GIF's progress bar, above the buttons.
  var gifScrubber: GIFScrubber?
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

      if let gifScrubber {
        GIFProgressBar(scrubber: gifScrubber)
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
      .compositingGroup()
      .frame(maxWidth: .infinity)
    }
    .multilineTextAlignment(.leading)
    .foregroundColor(.white)
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
