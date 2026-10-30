//
//  injectInTabDestinations.swift
//  Helio
//
//  Created by Igor Marcossi on 02/09/23.
//

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
    self
//      .attachViewControllerToRouter()
      .navigationDestination(for: Router.NavDest.self, destination: { dest in
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
          case .accessibility:
            AccessibilityPanel()
          case .filteredSubreddits:
            FilteredSubredditsSettings()
          case .faq:
            FAQPanel()
          case .themes:
            ThemesPanel()
          }
        }
      })
  }
}

private struct AttachViewControllerToRouterView: UIViewRepresentable {
  var tabID: Nav.TabIdentifier
  var disable: Bool
  func makeUIView(context: Context) -> some UIView {
    UIView()
  }

  func updateUIView(_ uiView: UIViewType, context: Context) {
    DispatchQueue.main.async {
      if let controller = uiView.parentViewController {
        Nav.shared[tabID].navController.controller = controller
      }
      Nav.shared[tabID].navController.setSwipeAnywhereEnabled(!disable)
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
