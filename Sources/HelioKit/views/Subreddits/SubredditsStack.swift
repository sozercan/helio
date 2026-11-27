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
  @AppStorage(DuoSplitDividerGeometry.defaultShareKey) private var savedDuoFeedShare: Double = 0
  @GestureState private var dragFeedWidth: CGFloat?

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
    let totalWidth = frame.width
    let share: CGFloat? = savedDuoFeedShare > 0 ? CGFloat(savedDuoFeedShare) : nil
    let settledFeedWidth = DuoSplitDividerGeometry.resolvedFeedWidth(
      savedShare: share,
      totalWidth: totalWidth,
      defaultWidth: layout.feedPaneWidth,
    )
    let activeFeedWidth = dragFeedWidth ?? settledFeedWidth
    let canResize = DuoSplitDividerGeometry.canResize(totalWidth: totalWidth)
    let fallbackBase = DuoSplitDividerGeometry.availablePaneWidth(totalWidth: totalWidth) / 2
    return HStack(spacing: 0) {
      feedPane
        .environment(\.paneHingeEdges, .trailing)
        .frame(width: activeFeedWidth)
      if canResize {
        paneDivider(baseWidth: settledFeedWidth ?? fallbackBase, totalWidth: totalWidth)
      } else {
        Divider()
      }
      postColumn(layout)
        .environment(\.paneHingeEdges, .leading)
        .environment(\.horizontalSizeClass, .compact)
    }
  }

  private func paneDivider(baseWidth: CGFloat, totalWidth: CGFloat) -> some View {
    ZStack {
      Divider()
      Capsule()
        .fill(Color.secondary.opacity(dragFeedWidth != nil ? 0.85 : 0.4))
        .frame(width: 4, height: 36)
    }
    .frame(width: DuoSplitDividerGeometry.dividerWidth)
    .contentShape(Rectangle())
    .gesture(
      DragGesture(minimumDistance: 4)
        .updating($dragFeedWidth) { value, state, _ in
          state = DuoSplitDividerGeometry.clampedWidth(baseWidth + value.translation.width, totalWidth: totalWidth)
        }
        .onEnded { value in
          let finalWidth = DuoSplitDividerGeometry.clampedWidth(baseWidth + value.translation.width, totalWidth: totalWidth)
          savedDuoFeedShare = Double(DuoSplitDividerGeometry.snappedShare(forWidth: finalWidth, totalWidth: totalWidth))
        },
    )
    .onTapGesture(count: 2) {
      savedDuoFeedShare = 0.5
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Resize feed and post panes")
    .accessibilityValue("\(Int((DuoSplitDividerGeometry.share(forWidth: baseWidth, totalWidth: totalWidth) * 100).rounded())) percent")
    .accessibilityAdjustableAction { direction in
      let step: CGFloat = direction == .increment ? 0.05 : -0.05
      let current = DuoSplitDividerGeometry.share(forWidth: baseWidth, totalWidth: totalWidth)
      let available = DuoSplitDividerGeometry.availablePaneWidth(totalWidth: totalWidth)
      let nextWidth = DuoSplitDividerGeometry.clampedWidth((current + step) * available, totalWidth: totalWidth)
      savedDuoFeedShare = Double(DuoSplitDividerGeometry.share(forWidth: nextWidth, totalWidth: totalWidth))
    }
    .accessibilityAction(named: "Equal Widths") {
      savedDuoFeedShare = 0.5
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
    let restoredDestination: Router.NavDest? = if behaviorDefSettings.restoreReadingSession,
                                                  let accountID = generalDefSettings.redditCredentialSelectedID,
                                                  let saved = ReadingSessionStore.load(accountID: accountID)
    {
      ReadingSessionStore.destination(forSavedFeedName: saved.feedName, accountID: accountID)
    } else {
      nil
    }
    if router.firstSelected == nil, let restoredDestination {
      router.firstSelected = restoredDestination
    } else if let feed = Self.launchFeed(defaultFeed: behaviorDefSettings.preferenceDefaultFeed, showsColumns: layout.showsColumns, current: router.firstSelected) {
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
