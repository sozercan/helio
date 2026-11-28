import Defaults
import SwiftUI

struct AttachViewControllerToRouterModifier: ViewModifier {
  var tabID: Nav.TabIdentifier
  @Default(.BehaviorDefSettings) private var behaviorDefSettings

  func body(content: Content) -> some View {
    content
      .background { AttachViewControllerToRouterView(tabID: tabID, disable: !behaviorDefSettings.enableSwipeAnywhere) }
  }
}

extension View {
  func attachViewControllerToRouter(tabID: Nav.TabIdentifier) -> some View {
    self.modifier(AttachViewControllerToRouterModifier(tabID: tabID))
  }

  func injectInTabDestinations() -> some View {
    navigationDestination(for: Router.NavDest.self) { RouterDestinationView(dest: $0) }
  }
}

struct RouterDestinationView: View {
  let dest: Router.NavDest

  var body: some View {
    Group {
      if case let .web(url) = dest {
        WebPageScreen(url: url)
      } else {
        screen.readableWidth()
      }
    }
    .ignoresPaneHingeInsets()
  }

  @ViewBuilder
  private var screen: some View {
    switch dest {
    case let .reddit(reddDest):
      switch reddDest {
      case let .post(post):
        if let sub = post.helioData?.subreddit {
          PostView(post: post, subreddit: sub)
        }
      case let .postHighlighted(post, highlightID):
        if let sub = post.helioData?.subreddit {
          PostView(post: post, subreddit: sub, highlightID: highlightID)
        }
      case let .subFeed(sub):
        SubredditPosts(subreddit: sub)
      case let .subInfo(sub):
        SubredditInfo(subreddit: sub)
      case let .multiFeed(multi):
        MultiPostsView(multi: multi)
      case .multiInfo:
        EmptyView()
      case let .user(user):
        UserView(user: user)
      case .friends:
        FriendsView()
      }
    case let .setting(settingsDest):
      switch settingsDest {
      case .general:
        GeneralPanel()
      case .behavior:
        BehaviorPanel()
      case .appearance:
        AppearancePanel()
      case .credentials:
        CredentialsPanel()
      case .about:
        AboutPanel()
      case .commentSwipe:
        CommentSwipePanel()
      case .postSwipe:
        PostSwipePanel()
      case .filteredSubreddits:
        FilteredSubredditsSettings()
      case .faq:
        FAQPanel()
      case .themes:
        ThemesPanel()
      case .webExtensions:
        WebExtensionsPanel()
      }
    case .web:
      EmptyView()
    }
  }
}

private struct AttachViewControllerToRouterView: UIViewRepresentable {
  var tabID: Nav.TabIdentifier
  var disable: Bool
  func makeUIView(context: Context) -> AttachControllerView {
    let view = AttachControllerView()
    view.tabID = tabID
    view.swipeAnywhereEnabled = !disable
    return view
  }

  func updateUIView(_ uiView: AttachControllerView, context: Context) {
    uiView.tabID = tabID
    uiView.swipeAnywhereEnabled = !disable
    uiView.attachToRouter()
  }
}

private final class AttachControllerView: UIView {
  var tabID: Nav.TabIdentifier = .posts
  var swipeAnywhereEnabled = false

  override func didMoveToWindow() {
    super.didMoveToWindow()
    attachToRouter()
  }

  func attachToRouter() {
    let tabID = tabID
    let swipeAnywhereEnabled = swipeAnywhereEnabled
    Task { @MainActor [weak self] in
      if let controller = self?.parentViewController {
        Nav.shared[tabID].navController.attach(controller)
      }
      Nav.shared[tabID].navController.setSwipeAnywhereEnabled(swipeAnywhereEnabled)
    }
  }
}

private extension UIView {
  var parentViewController: UIViewController? {
    sequence(first: self) {
      $0.next
    }.first(where: { $0 is UIViewController }) as? UIViewController
  }
}
