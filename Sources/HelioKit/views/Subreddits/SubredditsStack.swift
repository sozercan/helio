import Defaults
import SwiftUI

struct SubredditsStack: View {
  @State var router: Router
  @Default(.BehaviorDefSettings) private var behaviorDefSettings
  @Default(.GeneralDefSettings) private var generalDefSettings
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  @Environment(\.useTheme) private var selectedTheme
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var frame: CGRect = .zero

  init(router: Router) {
    self._router = .init(initialValue: router)
  }

  @State private var loaded = false
  @State private var layoutSwitch = LayoutSwitch()

  var body: some View {
    let layout = SplitLayout(sizeClass: horizontalSizeClass, frame: frame, division: WindowMetrics.shared.divisionFrame)
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
    .environment(\.horizontalSizeClass, layout.showsColumns ? .regular : .compact)
  }

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

  @ViewBuilder
  private func subsList(inSidebar: Bool) -> some View {
    if let redditCredentialSelectedID = generalDefSettings.redditCredentialSelectedID {
      Subreddits(firstDestination: sidebarSelection(inSidebar: inSidebar), loaded: loaded, currentCredentialID: redditCredentialSelectedID, inSidebar: inSidebar)
        .id("subreddits-list-\(redditCredentialSelectedID)")
        .attachViewControllerToRouter(tabID: .posts)
        .environment(\.navColumn, .feed)
        .hidesSidebarToggleOnMac()
    }
  }

  private func postColumn(_ layout: SplitLayout) -> some View {
    NavigationStack(path: $router.postPath) {
      Group {
        if let post = router.postColumn.first {
          RouterDestinationView(dest: post)
            .id(post)
            .hidesNavigationBarOnMac(layout.showsColumns)
            .closesWebPage(post, router: router)
        } else {
          ContentUnavailableView("No Post Selected", systemImage: "doc.text.image", description: Text("Choose a post from the feed."))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .themedListBG(selectedTheme.posts.bg)
        }
      }
      .ignoresPaneHingeInsets()
      .attachViewControllerToRouter(tabID: .posts)
      .injectInTabDestinations()
    }
    .environment(\.navColumn, .post)
    .columnContentWidth()
  }

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

  static func launchFeed(defaultFeed: String, showsColumns: Bool, current: Router.NavDest?) -> Router.NavDest? {
    guard current == nil else { return nil }
    if defaultFeed != "subList" {
      return .reddit(.subFeed(QuickAction.subreddit(named: defaultFeed)))
    }
    return showsColumns ? .reddit(.subFeed(Subreddit(id: "home"))) : nil
  }

  private func sidebarSelection(inSidebar: Bool) -> Binding<Router.NavDest?> {
    Binding {
      router.firstSelected
    } set: { dest in
      if dest != nil || !inSidebar {
        router.firstSelected = dest
      }
    }
  }

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
          .id("\(Router.NavDest.reddit(.subFeed(sub)).subredditFeedName ?? sub.id)-sub-first-tab")
      case let .reddit(.post(post)):
        if let sub = post.helioData?.subreddit {
          PostView(post: post, subreddit: sub)
            .id("\(post.id)-post-first-tab")
            .attachViewControllerToRouter(tabID: .posts)
        }
      case let .reddit(.postHighlighted(post, highlightID)):
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

struct SplitLayout: Equatable {
  static let minFeedWidth: CGFloat = 320
  static let idealFeedWidth: CGFloat = 400
  static let maxFeedWidth: CGFloat = 480
  static let minPostWidth: CGFloat = 440
  static let sidebarWidth: CGFloat = 320

  let showsColumns: Bool
  let usesPanes: Bool
  let fitsSidebar: Bool
  let measured: Bool
  let hingeFeedWidth: CGFloat?
  let hingeWidth: CGFloat

  var feedPaneWidth: CGFloat? {
    hingeFeedWidth.map { min($0 + hingeWidth / 2, Self.idealFeedWidth) }
  }

  var sidebarBesideFeed: Bool {
    showsColumns && !usesPanes
  }

  init(sizeClass: UserInterfaceSizeClass?, frame: CGRect, division: CGRect?) {
    let width = frame.width
    let measured = width > 0
    self.measured = measured
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
  func hidesNavigationBarOnMac(_ hidden: Bool) -> some View {
    #if targetEnvironment(macCatalyst)
      toolbar(hidden ? .hidden : .automatic, for: .navigationBar)
    #else
      self
    #endif
  }

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

  func hidesSidebarToggleOnMac() -> some View {
    #if targetEnvironment(macCatalyst)
      toolbar(removing: .sidebarToggle)
    #else
      self
    #endif
  }
}
