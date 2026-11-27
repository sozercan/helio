import SwiftUI

extension View {
  func openFromWebListener() -> some View {
    self
      .onOpenURL { url in
        let parsed = parseRedditURL(url.absoluteString)
        let reset = Nav.shared.activeTab != .posts
        withAnimation {
          switch parsed {
          case let .post(postID, subID):
            Nav.fullTo(.posts, .reddit(.post(Post(id: postID, subID: subID))), reset)
          case let .subreddit(name):
            Nav.fullTo(.posts, .reddit(.subFeed(Subreddit(id: name))), reset)
          case let .user(username):
            Nav.fullTo(.posts, .reddit(.user(User(id: username))), reset)
          default:
            let urlStringWithoutScheme = url.absoluteString.replacingOccurrences(of: "helioapp://", with: "")

            if let safariURL = URL(string: "https://" + urlStringWithoutScheme) {
              if isImageUrl(safariURL.absoluteString) {
                let imageView = ImageView(url: safariURL)
                let hostingController = UIHostingController(rootView: imageView)
                hostingController.overrideUserInterfaceStyle = .dark
                UIApplication.shared.firstKeyWindow?.rootViewController?.present(hostingController, animated: true)
              } else {
                Nav.openURL(safariURL)
              }
            }
          }
        }
      }
  }
}
