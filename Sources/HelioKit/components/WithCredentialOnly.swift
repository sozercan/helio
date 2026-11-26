import SwiftUI

struct WithCredentialOnly<Content: View>: View {
  let credential: RedditCredential?
  @ViewBuilder let content: () -> Content
  var body: some View {
    if let credential, credential.isWebSession, credential.webSessionCookies == nil {
      signedOut(credential)
    } else if !((credential?.validationStatus ?? .invalid) == .authorized) {
      VStack(spacing: 20) {
        VStack(spacing: 12) {
          Image(systemName: credential == nil ? "questionmark.key.filled" : "key.slash.fill")
            .fontSize(64, .bold)
            .opacity(0.5)
          VStack(spacing: 4) {
            Text(credential == nil ? "No credential" : "Credential invalid")
              .fontSize(24, .bold)
              .foregroundStyle(Color.secondaryText)
            Text("We can't load this page 😔").fontSize(16, .medium).foregroundStyle(Color.secondaryText)
          }
        }
        Button("Go to credentials settings", systemImage: "gear") {
          Nav.fullTo(.settings, .setting(.credentials))
        }
        .buttonStyle(.actionOutlined)
        .opacity(0.5)

        if credential != nil {
          AccountSwitcherMenu()
            .buttonStyle(.actionOutlined)
        }
      }
      .compositingGroup()
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      content()
    }
  }

  private func signedOut(_ credential: RedditCredential) -> some View {
    VStack(spacing: 20) {
      VStack(spacing: 12) {
        Image(systemName: "person.crop.circle.badge.exclamationmark.fill")
          .fontSize(64, .bold)
          .opacity(0.5)
        VStack(spacing: 4) {
          Text("Reddit signed you out")
            .fontSize(24, .bold)
            .foregroundStyle(Color.secondaryText)
          if let userName = credential.userName {
            Text("Sign in again as u/\(userName) to keep going.").fontSize(16, .medium).foregroundStyle(Color.secondaryText)
          }
        }
      }
      Button("Sign in again", systemImage: "person.crop.circle.badge.checkmark") {
        Nav.present(.redditSignIn(credential))
      }
      .buttonStyle(.action)

      AccountSwitcherMenu()
        .buttonStyle(.actionOutlined)
    }
    .compositingGroup()
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
