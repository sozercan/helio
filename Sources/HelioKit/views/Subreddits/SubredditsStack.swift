//
//  SubredditsStack.swift
//  Helio
//
//  Created by Igor Marcossi on 19/09/23.
//

import Defaults
import SwiftUI

/// The posts tab: the subs sidebar, the feed, and the open post. Wide windows show the feed and
/// the post side by side; narrow ones collapse the three into one stack of the same path.
struct SubredditsStack: View {
  @State var router: Router
  @Default(.BehaviorDefSettings) private var behaviorDefSettings // handle default feed selection routing
  @Default(.GeneralDefSettings) private var generalDefSettings // handle default feed selection routing
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  /// The split view collapses into one stack in compact width.
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  /// The split view's measured frame. Follows window resizes, unlike a screen-size calculation.
  @State private var frame: CGRect = .zero

  init(router: Router) {
    self._router = .init(initialValue: router)
  }

  @State private var loaded = false

  var body: some View {
    let layout = SplitLayout(sizeClass: horizontalSizeClass, frame: frame, division: WindowMetrics.shared.divisionFrame)
    NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: compactColumn) {
      if let redditCredentialSelectedID = generalDefSettings.redditCredentialSelectedID {
        Subreddits(firstDestination: sidebarSelection(showsColumns: layout.showsColumns), loaded: loaded, currentCredentialID: redditCredentialSelectedID, inSidebar: layout.showsColumns)
          .id("subreddits-list-\(redditCredentialSelectedID)")
          .attachViewControllerToRouter(tabID: .posts)
          // A post opened from the sidebar's saved posts replaces the open one.
          .environment(\.navColumn, .feed)
          .hidesSidebarToggleOnMac()
      }
    } content: {
      NavigationStack(path: $router.feedPath) {
        feedRoot
          .readableWidth()
          .injectInTabDestinations()
          .hidesSidebarToggleOnMac()
      }
      .environment(\.navColumn, .feed)
      .columnContentWidth()
      .feedColumnWidth(columnVisibility == .all ? nil : layout.hingeFeedWidth)
    } detail: {
      NavigationStack(path: $router.postPath) {
        Group {
          if let post = router.postColumn.first {
            // Keyed by the whole destination: two comments from one post are different threads.
            RouterDestinationView(dest: post)
              .id(post)
              .hidesNavigationBarOnMac(layout.showsColumns)
          } else {
            ContentUnavailableView("No Post Selected", systemImage: "doc.text.image", description: Text("Choose a post from the feed."))
          }
        }
        .attachViewControllerToRouter(tabID: .posts)
        .injectInTabDestinations()
      }
      .environment(\.navColumn, .post)
      .columnContentWidth()
    }
    .navigationSplitViewStyle(.balanced)
    // Too narrow for the feed and a post side by side (a narrow iPad or Mac window), the split view
    // collapses into one stack as it does in compact width; across a hinge it never does.
    .environment(\.horizontalSizeClass, layout.showsColumns ? .regular : .compact)
    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { newFrame in
      frame = newFrame
      chooseLaunchFeed(in: newFrame)
    }
    .onChange(of: layout.showsColumns, initial: true) { _, showsColumns in
      router.firstIsSidebarSelection = showsColumns
    }
    .onChange(of: layout.fitsSidebar, initial: true) { _, fits in
      columnVisibility = fits ? .all : .doubleColumn
    }
  }

  /// Opens the launch feed once the window's width is measured: before that, the size class alone
  /// would take a narrow regular-width window for one with the feed beside the subs list.
  private func chooseLaunchFeed(in frame: CGRect) {
    let layout = SplitLayout(sizeClass: horizontalSizeClass, frame: frame, division: WindowMetrics.shared.divisionFrame)
    guard !loaded, layout.measured else { return }
    if let feed = Self.launchFeed(defaultFeed: behaviorDefSettings.preferenceDefaultFeed, showsColumns: layout.showsColumns, current: router.firstSelected) {
      router.firstSelected = feed
    }
    withAnimation {
      loaded = true
    }
  }

  /// The feed the posts tab opens on: the default launch feed, else Home where the feed shows
  /// beside the subs list, which would otherwise leave the feed column empty. Nil keeps a feed
  /// already chosen, such as by a Home Screen quick action, or opens on the subs list.
  static func launchFeed(defaultFeed: String, showsColumns: Bool, current: Router.NavDest?) -> Router.NavDest? {
    guard current == nil else { return nil }
    if defaultFeed != "subList" {
      return .reddit(.subFeed(QuickAction.subreddit(named: defaultFeed)))
    }
    return showsColumns ? .reddit(.subFeed(Subreddit(id: "home"))) : nil
  }

  /// The subs list's selection. Beside the feed, the list can't clear it (as a Command-click
  /// would on Mac), which would empty the feed column; in a stack, Back clears it.
  private func sidebarSelection(showsColumns: Bool) -> Binding<Router.NavDest?> {
    Binding {
      router.firstSelected
    } set: { dest in
      if dest != nil || !showsColumns {
        router.firstSelected = dest
      }
    }
  }

  /// The feed at the root of the feed column: the sidebar's selection.
  @ViewBuilder
  private var feedRoot: some View {
    if let firstSelected = router.firstSelected {
      switch firstSelected {
      case let .reddit(.multiFeed(multi)):
        MultiPostsView(multi: multi)
          .id("\(multi.id)-multi-first-tab")
          .attachViewControllerToRouter(tabID: .posts)
      case let .reddit(.subFeed(sub)):
        SubredditPosts(subreddit: sub)
          // By the feed's name, which stays put when a feed opened by name takes in its
          // subreddit's details (and with them Reddit's id), so it keeps its pages.
          .id("\(Router.NavDest.reddit(.subFeed(sub)).subredditFeedName ?? sub.id)-sub-first-tab")
      case let .reddit(.post(post)):
        if let sub = post.helioData?.subreddit {
          PostView(post: post, subreddit: sub)
            .id("\(post.id)-post-first-tab")
            .attachViewControllerToRouter(tabID: .posts)
        }
      case let .reddit(.postHighlighted(post, highlightID)):
        // A comment link opened before a feed was chosen (from Me or Search).
        if let sub = post.helioData?.subreddit {
          PostView(post: post, subreddit: sub, highlightID: highlightID)
            .id("\(post.id)-\(highlightID)-post-first-tab")
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

  /// Which column the collapsed split view shows: the open post, else the feed, else the subs.
  /// Going back from the post or the feed there closes it.
  private var compactColumn: Binding<NavigationSplitViewColumn> {
    Binding {
      router.postColumnStart != nil ? .detail : router.firstSelected != nil ? .content : .sidebar
    } set: { column in
      guard !router.firstIsSidebarSelection else { return }
      if column == .content {
        router.closePost()
      } else if column == .sidebar {
        router.firstSelected = nil
      }
    }
  }
}

/// How the posts split view lays out its columns for a window width.
struct SplitLayout: Equatable {
  static let minFeedWidth: CGFloat = MacIdiom.size(320)
  static let idealFeedWidth: CGFloat = MacIdiom.size(400)
  static let maxFeedWidth: CGFloat = MacIdiom.size(480)
  /// The narrowest post column worth reading in. Narrower, the post replaces the feed.
  static let minPostWidth: CGFloat = MacIdiom.size(440)
  /// The sidebar's width when shown beside the other two.
  static let sidebarWidth: CGFloat = MacIdiom.size(320)

  /// The feed and the post side by side, else one stack. The open iPhone Duo always shows both,
  /// one on each side of the hinge, where a single column would be cut in two.
  let showsColumns: Bool
  /// Room for the sidebar beside them.
  let fitsSidebar: Bool
  /// Whether the window's width is known. Until it is, the size class decides.
  let measured: Bool
  /// The feed column's width that ends it at a vertical hinge, when there is one.
  let hingeFeedWidth: CGFloat?

  init(sizeClass: UserInterfaceSizeClass?, frame: CGRect, division: CGRect?) {
    let width = frame.width
    let measured = width > 0
    self.measured = measured
    // Only a vertical hinge separates a left and a right column.
    let division = division.flatMap { $0.height > $0.width ? $0 : nil }
    showsColumns = division != nil || (sizeClass != .compact && (!measured || width >= Self.minFeedWidth + Self.minPostWidth))
    fitsSidebar = showsColumns && (!measured || width >= Self.sidebarWidth + Self.idealFeedWidth + Self.minPostWidth)
    if let division, measured, division.minX > frame.minX, division.maxX < frame.maxX {
      hingeFeedWidth = division.minX - frame.minX
    } else {
      hingeFeedWidth = nil
    }
  }
}

private extension View {
  /// The feed column ends at the hinge when there's one (and no sidebar before it), else it
  /// takes a phone-like width.
  /// One modifier either way, so folding or unfolding doesn't rebuild the feed's stack (and lose
  /// its pages, filter and scroll position): at a hinge, all three widths are the hinge's.
  func feedColumnWidth(_ hingeWidth: CGFloat?) -> some View {
    navigationSplitViewColumnWidth(
      min: hingeWidth ?? SplitLayout.minFeedWidth,
      ideal: hingeWidth ?? SplitLayout.idealFeedWidth,
      max: hingeWidth ?? SplitLayout.maxFeedWidth,
    )
  }

  /// Beside the feed on Mac, the open post needs no bar of its own under the window toolbar:
  /// its actions are in that toolbar (`MacTabToolbar`), its subreddit is in its header, and at
  /// the column's root there's no Back. Screens opened over it get their bar, with Back.
  @ViewBuilder
  func hidesNavigationBarOnMac(_ hidden: Bool) -> some View {
    #if targetEnvironment(macCatalyst)
      toolbar(hidden ? .hidden : .automatic, for: .navigationBar)
    #else
      self
    #endif
  }

  /// The Mac window toolbar has the sidebar button (`MacTabToolbar`).
  @ViewBuilder
  func hidesSidebarToggleOnMac() -> some View {
    #if targetEnvironment(macCatalyst)
      toolbar(removing: .sidebarToggle)
    #else
      self
    #endif
  }
}
