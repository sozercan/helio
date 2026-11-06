//
//  SubredditsStack.swift
//  Helio
//
//  Created by Igor Marcossi on 19/09/23.
//

import Defaults
import SwiftUI

/// The posts tab: the subs sidebar, the feed, and the open post. Wide windows show the feed and
/// the post side by side; narrow ones collapse the three into one stack of the same path. The open
/// iPhone Duo shows them as two panes: the feed on the left and the post filling the rest.
struct SubredditsStack: View {
  @State var router: Router
  @Default(.BehaviorDefSettings) private var behaviorDefSettings // handle default feed selection routing
  @Default(.GeneralDefSettings) private var generalDefSettings // handle default feed selection routing
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  @Environment(\.useTheme) private var selectedTheme
  /// The split view collapses into one stack in compact width.
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  /// The split view's measured frame. Follows window resizes, unlike a screen-size calculation.
  @State private var frame: CGRect = .zero

  init(router: Router) {
    self._router = .init(initialValue: router)
  }

  @State private var loaded = false
  /// Which of the two layouts shows, to hand the screens' state to the other one's.
  @State private var layoutSwitch = LayoutSwitch()

  var body: some View {
    let layout = SplitLayout(sizeClass: horizontalSizeClass, frame: frame, division: WindowMetrics.shared.divisionFrame)
    // Before the new layout's screens are built, so they take over the old ones' state.
    let _ = layoutSwitch.show(usesPanes: layout.usesPanes)
    Group {
      if layout.usesPanes {
        panes(layout)
      } else {
        splitView(layout)
      }
    }
    .environment(\.screenStateScope, layoutSwitch)
    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { newFrame in
      frame = newFrame
      chooseLaunchFeed(in: newFrame)
    }
    .onChange(of: layout.showsColumns, initial: true) { _, showsColumns in
      router.showsPostBesideFeed = showsColumns
    }
    .onChange(of: layout.sidebarBesideFeed, initial: true) { _, besideFeed in
      router.firstIsSidebarSelection = besideFeed
    }
    .onChange(of: layout.fitsSidebar, initial: true) { _, fits in
      columnVisibility = fits ? .all : .doubleColumn
    }
  }

  /// Switching between the panes and the split view builds every screen anew: tells
  /// `ScreenStates`, so the new screens keep the feed's place, the post's comments and the web
  /// page's history. Not observed, as it changes while the view updates.
  @MainActor
  private final class LayoutSwitch {
    private var usesPanes: Bool?

    func show(usesPanes: Bool) {
      if let shown = self.usesPanes, shown != usesPanes {
        ScreenStates.shared.beginHandoff(in: self)
      }
      self.usesPanes = usesPanes
    }
  }

  /// Subs, feed and post as the split view's three columns, or collapsed into one stack.
  private func splitView(_ layout: SplitLayout) -> some View {
    NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: compactColumn) {
      subsList(inSidebar: layout.showsColumns)
    } content: {
      NavigationStack(path: $router.feedPath) {
        feedRoot
          .readableWidth()
          .injectInTabDestinations()
          .hidesSidebarToggleOnMac()
      }
      .environment(\.navColumn, .feed)
      .columnContentWidth()
      .navigationSplitViewColumnWidth(min: SplitLayout.minFeedWidth, ideal: SplitLayout.idealFeedWidth, max: SplitLayout.maxFeedWidth)
    } detail: {
      postColumn(layout)
    }
    .navigationSplitViewStyle(.balanced)
    // Too narrow for the feed and a post side by side (a narrow iPad or Mac window), the split view
    // collapses into one stack as it does in compact width.
    .environment(\.horizontalSizeClass, layout.showsColumns ? .regular : .compact)
  }

  /// The open iPhone Duo: the subs list and the feed on the left, the post filling the rest on the
  /// right, each its own stack. The split view would cover the post with the feed there, as
  /// neither half is as wide as its columns need.
  ///
  /// Not `ArrangementView`: lying flat, it splits the space left of the side tab bar in half, so
  /// the post pane ran across the hinge.
  ///
  /// The feed pane takes a feed column's width, up to the hinge, and the post pane the rest, with
  /// a hairline between them.
  ///
  /// This view is laid out inside the safe area, left of the side tab bar. Each pane's screens
  /// ignore the inset on their hinge side: a navigation stack in the feed pane gets the tab bar's
  /// inset though it ends at the hinge, which narrowed its lists twice. The post pane keeps the tab
  /// bar's inset; ignoring it there ran the post under the tab bar.
  private func panes(_ layout: SplitLayout) -> some View {
    HStack(spacing: 0) {
      feedPane
        .environment(\.paneHingeEdges, .trailing)
        .frame(width: layout.feedPaneWidth)
      Divider()
      postColumn(layout)
        .environment(\.paneHingeEdges, .leading)
        .environment(\.horizontalSizeClass, .compact)
    }
  }

  /// The subs list with the feed and what's opened from it stacked on it, as in one stack.
  private var feedPane: some View {
    NavigationStack(path: $router.feedPanePath) {
      subsList(inSidebar: false)
        .ignoresPaneHingeInsets()
        .injectInTabDestinations()
    }
    .environment(\.navColumn, .feed)
    .columnContentWidth()
    .environment(\.horizontalSizeClass, .compact)
  }

  /// The subs list: the split view's sidebar beside the feed, else the first screen of a stack.
  @ViewBuilder
  private func subsList(inSidebar: Bool) -> some View {
    if let redditCredentialSelectedID = generalDefSettings.redditCredentialSelectedID {
      Subreddits(firstDestination: sidebarSelection(inSidebar: inSidebar), loaded: loaded, currentCredentialID: redditCredentialSelectedID, inSidebar: inSidebar)
        .id("subreddits-list-\(redditCredentialSelectedID)")
        .attachViewControllerToRouter(tabID: .posts)
        // A post opened from the sidebar's saved posts replaces the open one.
        .environment(\.navColumn, .feed)
        .hidesSidebarToggleOnMac()
    }
  }

  /// The open post and the screens opened from it, or a placeholder.
  private func postColumn(_ layout: SplitLayout) -> some View {
    NavigationStack(path: $router.postPath) {
      Group {
        if let post = router.postColumn.first {
          // Keyed by the whole destination: two comments from one post are different threads.
          RouterDestinationView(dest: post)
            .id(post)
            .hidesNavigationBarOnMac(layout.showsColumns)
            .closesWebPage(post, router: router)
        } else {
          // On the post view's background, so the column doesn't change shade when a post opens.
          ContentUnavailableView("No Post Selected", systemImage: "doc.text.image", description: Text("Choose a post from the feed."))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .themedListBG(selectedTheme.posts.bg)
        }
      }
      // The post at the column's root, like the screens pushed on it (`injectInTabDestinations`).
      .ignoresPaneHingeInsets()
      .attachViewControllerToRouter(tabID: .posts)
      .injectInTabDestinations()
    }
    .environment(\.navColumn, .post)
    .columnContentWidth()
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
  private func sidebarSelection(inSidebar: Bool) -> Binding<Router.NavDest?> {
    Binding {
      router.firstSelected
    } set: { dest in
      if dest != nil || !inSidebar {
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
  static let minFeedWidth: CGFloat = 320
  static let idealFeedWidth: CGFloat = 400
  static let maxFeedWidth: CGFloat = 480
  /// The narrowest post column worth reading in. Narrower, the post replaces the feed.
  static let minPostWidth: CGFloat = 440
  /// The sidebar's width when shown beside the other two.
  static let sidebarWidth: CGFloat = 320

  /// The feed and the post side by side, else one stack. The open iPhone Duo always shows both,
  /// one on each side of the hinge, where a single column would be cut in two.
  let showsColumns: Bool
  /// Two panes split at a vertical hinge instead of the split view's columns. Neither half of the
  /// open Duo is as wide as a post column needs, so the split view would lay the feed over the post.
  let usesPanes: Bool
  /// Room for the sidebar beside them.
  let fitsSidebar: Bool
  /// Whether the window's width is known. Until it is, the size class decides.
  let measured: Bool
  /// The first pane's width, which ends it at a vertical hinge, when there is one.
  let hingeFeedWidth: CGFloat?
  /// The hinge's width, between the two panes.
  let hingeWidth: CGFloat

  /// The first pane's width: a feed column's, so the post gets the rest, but no further than the
  /// middle of the hinge.
  var feedPaneWidth: CGFloat? {
    hingeFeedWidth.map { min($0 + hingeWidth / 2, Self.idealFeedWidth) }
  }

  /// The subs list shows beside the feed, as the split view's sidebar. In one stack, and in the
  /// Duo's first pane, the feed is a screen pushed on it instead, which Back can leave.
  var sidebarBesideFeed: Bool {
    showsColumns && !usesPanes
  }

  init(sizeClass: UserInterfaceSizeClass?, frame: CGRect, division: CGRect?) {
    let width = frame.width
    let measured = width > 0
    self.measured = measured
    // Only a vertical hinge separates a left and a right column.
    let division = division.flatMap { $0.height > $0.width ? $0 : nil }
    usesPanes = division != nil
    showsColumns = division != nil || (sizeClass != .compact && (!measured || width >= Self.minFeedWidth + Self.minPostWidth))
    fitsSidebar = showsColumns && !usesPanes && (!measured || width >= Self.sidebarWidth + Self.idealFeedWidth + Self.minPostWidth)
    if let division, measured, division.minX > frame.minX, division.maxX < frame.maxX {
      hingeFeedWidth = division.minX - frame.minX
      hingeWidth = division.width
    } else {
      hingeFeedWidth = nil
      hingeWidth = 0
    }
  }
}

private extension View {
  /// Beside the feed on Mac, the open post needs no bar of its own under the window toolbar:
  /// its actions are in that toolbar (`MacTabToolbar`), its subreddit is in its header, and at
  /// the column's root there's no Back. Screens opened over it get their bar, with Back.
  func hidesNavigationBarOnMac(_ hidden: Bool) -> some View {
    #if targetEnvironment(macCatalyst)
      toolbar(hidden ? .hidden : .automatic, for: .navigationBar)
    #else
      self
    #endif
  }

  /// A web page opened from the feed, at the post column's root, has no post to go back to, so it
  /// gets Close. Not on Mac, where the column hides its bar and the window toolbar has its actions.
  @ViewBuilder
  func closesWebPage(_ dest: Router.NavDest, router: Router) -> some View {
    #if targetEnvironment(macCatalyst)
      self
    #else
      if case .web = dest {
        toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button("Close", systemImage: "xmark") {
              withAnimation { router.closePost() }
            }
          }
        }
      } else {
        self
      }
    #endif
  }

  /// The Mac window toolbar has the sidebar button (`MacTabToolbar`).
  func hidesSidebarToggleOnMac() -> some View {
    #if targetEnvironment(macCatalyst)
      toolbar(removing: .sidebarToggle)
    #else
      self
    #endif
  }
}
