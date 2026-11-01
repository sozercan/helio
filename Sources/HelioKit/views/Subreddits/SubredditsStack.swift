//
//  SubredditsStack.swift
//  Helio
//
//  Created by Igor Marcossi on 19/09/23.
//

import Defaults
import SwiftUI

struct SubredditsStack: View {
  @State var router: Router
  @Default(.BehaviorDefSettings) private var behaviorDefSettings // handle default feed selection routing
  @Default(.GeneralDefSettings) private var generalDefSettings // handle default feed selection routing
  @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
  /// The split view collapses into one stack in compact width.
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  /// The posts column's measured frame. Follows window resizes, unlike a screen-size calculation.
  @State private var detailFrame: CGRect = .zero

  init(router: Router) {
    self._router = .init(initialValue: router)
  }

  /// The column runs under the unfolded iPhone Duo's side tab bar while its posts stop at the
  /// window's safe area, so only the part inside that counts.
  var postContentWidth: CGFloat {
    guard detailFrame.width > 0 else { return .screenW }
    let visible = detailFrame.intersection(WindowMetrics.shared.contentFrame)
    return visible.width > 0 ? visible.width : detailFrame.width
  }

  @State private var loaded = false
  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      if let redditCredentialSelectedID = generalDefSettings.redditCredentialSelectedID {
        Subreddits(firstDestination: $router.firstSelected, loaded: loaded, currentCredentialID: redditCredentialSelectedID)
          .id("subreddits-list-\(redditCredentialSelectedID)")
          .attachViewControllerToRouter(tabID: .posts)
        #if targetEnvironment(macCatalyst)
          // The window toolbar has the Mac's sidebar button (`MacTabToolbar`).
          .toolbar(removing: .sidebarToggle)
        #endif
      }
    } detail: {
      NavigationStack(path: $router.path) {
        Group {
          if let firstSelected = router.firstSelected {
            switch firstSelected {
            case let .reddit(.multiFeed(multi)):
              MultiPostsView(multi: multi)
                .id("\(multi.id)-multi-first-tab")
                .attachViewControllerToRouter(tabID: .posts)
            case let .reddit(.subFeed(sub)):
              SubredditPosts(subreddit: sub)
                .id("\(sub.id)-sub-first-tab")
            case let .reddit(.post(post)):
              if let sub = post.helioData?.subreddit {
                PostView(post: post, subreddit: sub)
                  .id("\(post.id)-post-first-tab")
                  .attachViewControllerToRouter(tabID: .posts)
              }
            case let .reddit(.user(user)):
              UserView(user: user)
                .id("\(user.id)-user-first-tab")
                .attachViewControllerToRouter(tabID: .posts)
            default:
              EmptyView()
            }
          } else {
            ContentUnavailableView("No Feed Selected", systemImage: "rectangle.stack", description: Text("Pick a feed or subreddit."))
              .attachViewControllerToRouter(tabID: .posts)
          }
        }
        .injectInTabDestinations()
        .task(priority: .background) {
          if !loaded {
            // MARK: Route to default feed

            // Skipped when a feed is already chosen, such as by a Home Screen quick action.
            if behaviorDefSettings.preferenceDefaultFeed != "subList", router.firstSelected == nil { // we are in subList, can ignore
              let tempSubreddit = Subreddit(id: behaviorDefSettings.preferenceDefaultFeed)
              router.firstSelected = .reddit(.subFeed(tempSubreddit))
            }

            withAnimation {
              loaded = true
            }
          }
        }
      }
      .environment(\.contentWidth, postContentWidth)
      // Fill the column so this measures it rather than the content (the placeholder is 200pt).
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { detailFrame = $0 }
    }
//    .swipeAnywhere()
    // Side by side unless the sidebar is toggled off. In narrower wide windows (unfolded iPhone
    // Duo) the automatic style overlays the sidebar on the posts instead.
    .navigationSplitViewStyle(.balanced)
    .environment(\.contentWidth, postContentWidth)
    .onChange(of: horizontalSizeClass, initial: true) { _, sizeClass in
      router.firstIsSidebarSelection = sizeClass != .compact
    }
  }
}
