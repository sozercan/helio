//
//  CommandTargets.swift
//  Helio
//
//  What the menu bar's Refresh, Find and Post commands act on.
//

import SwiftUI

/// The screens the menu bar's commands act on. A screen registers while it shows
/// (`commandTarget(_:)`), so the commands follow what's on screen: in a single stack, the screen
/// on top; in the posts split view, the feed column's screen and the post column's post. The
/// screen shown last is the one Refresh and Find use, as it's the one the user went to last.
@Observable
final class CommandTargets {
  static let shared = CommandTargets()

  struct Target {
    /// `modal`: what covers the screens, such as a reply being written or a full-screen image or
    /// video. The commands must not act on the screens behind it, or close it by moving to another post.
    enum Kind { case feed, post, subs, search, profile, modal }

    var kind: Kind
    /// The posts split view's column it shows in.
    var column: Router.Column?
    var refresh: (() -> Void)?
    var focusSearch: (() -> Void)?
    /// A feed's posts, in order, for Next and Previous Post.
    var posts: (() -> [Post])?
    /// Scrolls a feed to one of its posts.
    var reveal: ((Post) -> Void)?
    /// Whether a feed has another page past its loaded posts, and loads it. A feed loads pages
    /// as its rows appear, which a feed covered by its post can't do.
    var canLoadMore: (() -> Bool)?
    var loadMore: (() async -> Void)?
    /// The post a post screen shows, for voting and replying.
    var post: Post?
    var reply: (() -> Void)?
    /// The screen's own actions, for the menu bar and the Mac window toolbar.
    var actions: [ScreenAction] = []

    func revealing(with proxy: ScrollViewProxy) -> Target {
      var target = self
      target.reveal = { post in withAnimation { proxy.scrollTo(post.id) } }
      return target
    }
  }

  private(set) var targets: [(id: UUID, target: Target)] = []

  /// Set by Find when no search field shows: the Search tab focuses its field when it next appears.
  @ObservationIgnored var searchFocusPending = false

  /// The feed shown last in the posts tab's feed column, for Next and Previous Post. Kept after
  /// it unregisters: in the collapsed stack, the post opened from it covers it.
  private var postsFeed: (id: UUID, target: Target)?

  func register(_ target: Target) -> UUID {
    let id = UUID()
    targets.append((id, target))
    if target.kind == .feed, target.column == .feed, target.posts != nil {
      postsFeed = (id, target)
    }
    return id
  }

  /// Replaces a registered target, as what its screen can do changes (its sort, its actions).
  func update(_ id: UUID, to target: Target) {
    guard let index = targets.firstIndex(where: { $0.id == id }) else { return }
    targets[index].target = target
    if postsFeed?.id == id {
      postsFeed = (id, target)
    }
  }

  func unregister(_ id: UUID) {
    targets.removeAll { $0.id == id }
  }

  /// Drops the posts feed kept for Next and Previous Post once its screen is gone for good (its
  /// stack discarded, as when the account changes), not just covered, so its posts and the
  /// credential its requests captured aren't kept.
  func forgetPostsFeed(_ id: UUID) {
    if postsFeed?.id == id {
      postsFeed = nil
    }
  }

  /// Hands the pending Find request to the Search tab, once.
  func takeSearchFocusRequest() -> Bool {
    defer { searchFocusPending = false }
    return searchFocusPending
  }

  // MARK: Commands

  private var refreshTarget: Target? {
    targets.last { $0.target.refresh != nil }?.target
  }

  /// Not while something covers the screens: the refresh would reload the screen behind it.
  var canRefresh: Bool {
    refreshTarget != nil && !isCoveredObservably()
  }

  func refresh() {
    guard refreshTarget != nil, !isCovered() else { return }
    refreshTarget?.refresh?()
  }

  /// Whether Find has a field to focus: one shown, or the Search tab's, which needs an account
  /// it can use (as `WithCredentialOnly` gates it).
  @MainActor
  func canFind() -> Bool {
    canFind(credential: RedditCredentialsManager.shared.selectedCredential)
  }

  func canFind(credential: RedditCredential?) -> Bool {
    if targets.contains(where: { $0.target.focusSearch != nil }) {
      return true
    }
    guard let credential, credential.validationStatus == .authorized else { return false }
    return !(credential.isWebSession && credential.webSessionCookies == nil)
  }

  /// Focuses the search field shown last, else switches to the Search tab and focuses its. The
  /// menu offers it only when `canFind()`.
  func find(nav: Nav = .shared) {
    guard !isCovered(nav: nav) else { return }
    if let focus = targets.last(where: { $0.target.focusSearch != nil })?.target.focusSearch {
      focus()
    } else {
      searchFocusPending = true
      // Back to the search itself, not a result left open there.
      nav[.search].fullPath = []
      nav.activeTab = .search
    }
  }

  /// The post shown last, for voting and replying.
  var openPost: Target? {
    targets.last { $0.target.kind == .post && $0.target.post != nil }?.target
  }

  /// The actions of the screen shown last in `column` (nil: outside the posts split view). In
  /// the posts tab, screens opened over a column's first one don't know their column: a post
  /// is taken to be in the post column, anything else in the feed column.
  func actions(in column: Router.Column?, postsTab: Bool = false) -> [ScreenAction] {
    targets.last { entry in
      let target = entry.target
      let resolved = postsTab ? target.column ?? (target.kind == .post ? .post : .feed) : target.column
      return resolved == column && !target.actions.isEmpty
    }?.target.actions ?? []
  }

  /// The action with `id` of the screen shown last that has one.
  func action(_ id: ScreenAction.ID) -> ScreenAction? {
    for (_, target) in targets.reversed() {
      if let action = target.actions.first(where: { $0.id == id }) {
        return action
      }
    }
    return nil
  }

  /// While a reply is being written, an image or video fills the screen, or a sheet such as
  /// sign-in shows, Find and the Post commands would act on the screen behind it, and moving to
  /// another post would close it.
  func isCovered(nav: Nav = .shared) -> Bool {
    isCoveredObservably(nav: nav) || Self.windowPresentsSomething()
  }

  /// The part of `isCovered` SwiftUI observes, for menu items' enabled state: UIKit's own
  /// presentations (a share sheet) don't redraw the menus, so a state that included them could
  /// stay disabled after they close. The commands check the whole of it when they run.
  func isCoveredObservably(nav: Nav = .shared) -> Bool {
    nav.presentingSheet != nil || showsModal
  }

  /// Anything presented over the window's root, such as the share sheet or a view's own sheet,
  /// which neither sets `Nav.presentingSheet` nor registers as a modal. Not an active search
  /// field: UIKit presents its search controller too, and Find and Refresh must still work then.
  static func windowPresentsSomething() -> Bool {
    guard Thread.isMainThread else { return false }
    return MainActor.assumeIsolated {
      // Up the whole chain: a share sheet can sit on an active search's controller.
      var presented = UIApplication.shared.firstKeyWindow?.rootViewController?.presentedViewController
      while let controller = presented {
        if !(controller is UISearchController) {
          return true
        }
        presented = controller.presentedViewController
      }
      return false
    }
  }

  var showsModal: Bool {
    targets.contains { $0.target.kind == .modal }
  }

  /// Whether Next or Previous Post can move from the post the posts tab's feed has open: to
  /// another loaded post, or past the last one when the feed has another page.
  func canOpenAdjacentPost(_ offset: Int, nav: Nav = .shared) -> Bool {
    guard nav.activeTab == .posts, !isCoveredObservably(nav: nav) else { return false }
    return canOpenAdjacentPost(offset, in: nav[.posts])
  }

  func canOpenAdjacentPost(_ offset: Int, in router: Router) -> Bool {
    adjacentPost(offset, in: router) != nil || needsNextPage(offset, in: router)
  }

  /// The post `offset` places from the post the posts tab's feed has open, among its loaded
  /// posts. Nil when no post from it is open, or past the loaded ones.
  func adjacentPost(_ offset: Int, in router: Router) -> Post? {
    guard let id = Self.feedPostID(in: router), let posts = postsFeed?.target.posts?() else { return nil }
    return Self.post(offset, from: id, in: posts)
  }

  /// Whether moving `offset` forward goes past the feed's loaded posts into a page it can load.
  private func needsNextPage(_ offset: Int, in router: Router) -> Bool {
    guard offset > 0, let feed = postsFeed?.target, feed.canLoadMore?() == true, let id = Self.feedPostID(in: router),
          let posts = feed.posts?(), let index = posts.firstIndex(where: { $0.id == id }) else { return false }
    return index + offset >= posts.count
  }

  /// Opens the post `offset` places from the open one in the post column and scrolls the feed to it.
  func openAdjacentPost(_ offset: Int, nav: Nav = .shared) {
    guard canOpenAdjacentPost(offset, nav: nav), !isCovered(nav: nav) else { return }
    openAdjacentPost(offset, in: nav[.posts]) { nav.activeTab == .posts && nav.presentingSheet == nil }
  }

  /// Past the loaded posts, loads the feed's next page first and returns the task doing so.
  /// `stillShown` tells whether the posts tab is still the one on screen once the page arrives.
  @discardableResult
  func openAdjacentPost(_ offset: Int, in router: Router, stillShown: @escaping () -> Bool = { true }) -> Task<Void, Never>? {
    guard adjacentPost(offset, in: router) == nil else {
      openLoadedPost(offset, in: router)
      return nil
    }
    guard needsNextPage(offset, in: router), let feed = postsFeed, let loadMore = feed.target.loadMore else { return nil }
    let path = router.fullPath
    return Task { @MainActor in
      // A page can hold no posts (Saved mixes in comments), so keep paging, a few pages at most,
      // until one arrives or the feed can't load more.
      for _ in 0 ..< Self.maxPagesPerStep {
        await loadMore()
        // Not if the user has moved on while the page loaded: to another tab, feed or screen, or
        // to a reply or a full-screen image.
        guard stillShown(), postsFeed?.id == feed.id, router.fullPath == path, !showsModal, !Self.windowPresentsSomething() else { return }
        if adjacentPost(offset, in: router) != nil {
          openLoadedPost(offset, in: router)
          return
        }
        // Not past a list the open post is no longer in (a refresh or filter replaced it).
        guard let id = Self.feedPostID(in: router), feed.target.posts?().contains(where: { $0.id == id }) == true,
              feed.target.canLoadMore?() == true else { return }
      }
    }
  }

  /// How many pages Next Post loads looking for a post before it stops.
  static let maxPagesPerStep = 3

  private func openLoadedPost(_ offset: Int, in router: Router) {
    guard let post = adjacentPost(offset, in: router) else { return }
    router.navigateTo(.reddit(.post(post)), from: .feed)
    // Only a feed that shows scrolls; a covered one keeps its place.
    if let feed = postsFeed, targets.contains(where: { $0.id == feed.id }) {
      feed.target.reveal?(post)
    }
  }

  /// The id of the post Next and Previous Post move from: the first in the post column, the one
  /// the feed marks as open. Beside the feed it moves even under screens opened from the post,
  /// as a list's selection does; in one stack, where the feed doesn't show, only from the post
  /// itself, not from a profile or another post opened over it.
  static func feedPostID(in router: Router) -> String? {
    // Only from a feed, the top screen of the feed column (a profile opened over a standalone
    // post registers its posts too): a post opened from elsewhere (the Posts Box, the subs list)
    // isn't in the feed kept from before.
    guard let feedTop = router.feedPath.last ?? router.fullPath.first, listsPosts(feedTop), let post = router.postColumn.first,
          router.firstIsSidebarSelection || router.postPath.isEmpty else { return nil }
    return post.id
  }

  /// A screen in the feed column that registers its posts as the feed: a subreddit or
  /// multireddit, or a profile.
  private static func listsPosts(_ dest: Router.NavDest) -> Bool {
    if case .reddit(.user) = dest {
      return true
    }
    return dest.isFeed
  }

  /// The post `offset` places from the one with `id` in `posts`.
  static func post(_ offset: Int, from id: String, in posts: [Post]) -> Post? {
    guard let index = posts.firstIndex(where: { $0.id == id }) else { return nil }
    let target = index + offset
    return posts.indices.contains(target) ? posts[target] : nil
  }
}

/// Lives as long as the screen's state: a covered screen keeps it, a discarded one frees it.
private final class CommandTargetLifetime {
  var registration: UUID?

  deinit {
    guard let registration else { return }
    Task { @MainActor in CommandTargets.shared.forgetPostsFeed(registration) }
  }
}

private struct CommandTargetModifier<Key: Equatable>: ViewModifier {
  var target: CommandTargets.Target?
  var key: Key
  @State private var registration: UUID?
  @State private var lifetime = CommandTargetLifetime()

  func body(content: Content) -> some View {
    content
      .onAppear {
        guard registration == nil, let target else { return }
        registration = CommandTargets.shared.register(target)
        lifetime.registration = registration
      }
      .onChange(of: key) {
        if let registration, let target {
          CommandTargets.shared.update(registration, to: target)
        }
      }
      .onDisappear {
        if let registration {
          CommandTargets.shared.unregister(registration)
        }
        registration = nil
      }
      // The actions show the screen's state, such as its sort: keep them current.
      .onChange(of: target?.actions ?? []) {
        if let registration, let target {
          CommandTargets.shared.update(registration, to: target)
        }
      }
  }
}

extension View {
  /// Makes this screen what the menu bar's commands act on while it shows. Nil registers nothing.
  func commandTarget(_ target: CommandTargets.Target?) -> some View {
    modifier(CommandTargetModifier(target: target, key: 0))
  }

  /// `commandTarget` whose target changes with `key`, such as a refresh that's only available
  /// with something to refresh.
  func commandTarget(_ target: CommandTargets.Target?, updatingWith key: some Equatable) -> some View {
    modifier(CommandTargetModifier(target: target, key: key))
  }

  /// `commandTarget` for a feed, which Next and Previous Post scroll to the post they open.
  func feedCommandTarget(_ target: CommandTargets.Target) -> some View {
    ScrollViewReader { proxy in
      commandTarget(target.revealing(with: proxy))
    }
  }
}
