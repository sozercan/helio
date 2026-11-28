import SwiftUI

@Observable
final class CommandTargets {
  static let shared = CommandTargets()

  struct Target {
    enum Kind { case feed, post, subs, search, profile, web, modal }

    var kind: Kind
    var column: Router.Column?
    var refresh: (() -> Void)?
    var focusSearch: (() -> Void)?
    var posts: (() -> [Post])?
    var reveal: ((Post) -> Void)?
    var canLoadMore: (() -> Bool)?
    var loadMore: (() async -> Void)?
    var post: Post?
    var reply: (() -> Void)?
    var actions: [ScreenAction] = []

    func revealing(with proxy: ScrollViewProxy) -> Target {
      var target = self
      target.reveal = { post in withAnimation { proxy.scrollTo(post.id) } }
      return target
    }
  }

  private(set) var targets: [(id: UUID, target: Target)] = []

  @ObservationIgnored var searchFocusPending = false

  private var postsFeed: (id: UUID, target: Target)?

  func register(_ target: Target) -> UUID {
    let id = UUID()
    targets.append((id, target))
    if target.kind == .feed, target.column == .feed, target.posts != nil {
      postsFeed = (id, target)
    }
    return id
  }

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

  func forgetPostsFeed(_ id: UUID) {
    if postsFeed?.id == id {
      postsFeed = nil
    }
  }

  func takeSearchFocusRequest() -> Bool {
    defer { searchFocusPending = false }
    return searchFocusPending
  }

  private var refreshTarget: Target? {
    targets.last { $0.target.refresh != nil }?.target
  }

  var canRefresh: Bool {
    refreshTarget != nil && !isCoveredObservably()
  }

  func refresh() {
    guard refreshTarget != nil, !isCovered() else { return }
    refreshTarget?.refresh?()
  }

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

  func find(nav: Nav = .shared) {
    guard !isCovered(nav: nav) else { return }
    if let focus = targets.last(where: { $0.target.focusSearch != nil })?.target.focusSearch {
      focus()
    } else {
      searchFocusPending = true
      nav[.search].fullPath = []
      nav.activeTab = .search
    }
  }

  var openPost: Target? {
    targets.last { $0.target.kind == .post && $0.target.post != nil }?.target
  }

  func actions(in column: Router.Column?, postsTab: Bool = false) -> [ScreenAction] {
    targets.last { entry in
      let target = entry.target
      let resolved = postsTab ? target.column ?? (target.kind == .post ? .post : .feed) : target.column
      return resolved == column && !target.actions.isEmpty
    }?.target.actions ?? []
  }

  func action(_ id: ScreenAction.ID) -> ScreenAction? {
    for (_, target) in targets.reversed() {
      if let action = target.actions.first(where: { $0.id == id }) {
        return action
      }
    }
    return nil
  }

  func isCovered(nav: Nav = .shared) -> Bool {
    isCoveredObservably(nav: nav) || Self.windowPresentsSomething()
  }

  func isCoveredObservably(nav: Nav = .shared) -> Bool {
    nav.presentingSheet != nil || showsModal
  }

  static func windowPresentsSomething() -> Bool {
    guard Thread.isMainThread else { return false }
    return MainActor.assumeIsolated {
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

  func canOpenAdjacentPost(_ offset: Int, nav: Nav = .shared) -> Bool {
    guard nav.activeTab == .posts, !isCoveredObservably(nav: nav) else { return false }
    return canOpenAdjacentPost(offset, in: nav[.posts])
  }

  func canOpenAdjacentPost(_ offset: Int, in router: Router) -> Bool {
    adjacentPost(offset, in: router) != nil || needsNextPage(offset, in: router)
  }

  func adjacentPost(_ offset: Int, in router: Router) -> Post? {
    guard let id = Self.feedPostID(in: router), let posts = postsFeed?.target.posts?() else { return nil }
    return Self.post(offset, from: id, in: posts)
  }

  private func needsNextPage(_ offset: Int, in router: Router) -> Bool {
    guard offset > 0, let feed = postsFeed?.target, feed.canLoadMore?() == true, let id = Self.feedPostID(in: router),
          let posts = feed.posts?(), let index = posts.firstIndex(where: { $0.id == id }) else { return false }
    return index + offset >= posts.count
  }

  func openAdjacentPost(_ offset: Int, nav: Nav = .shared) {
    guard canOpenAdjacentPost(offset, nav: nav), !isCovered(nav: nav) else { return }
    openAdjacentPost(offset, in: nav[.posts]) { nav.activeTab == .posts && nav.presentingSheet == nil }
  }

  @discardableResult
  func openAdjacentPost(_ offset: Int, in router: Router, stillShown: @escaping () -> Bool = { true }) -> Task<Void, Never>? {
    guard adjacentPost(offset, in: router) == nil else {
      openLoadedPost(offset, in: router)
      return nil
    }
    guard needsNextPage(offset, in: router), let feed = postsFeed, let loadMore = feed.target.loadMore else { return nil }
    let path = router.fullPath
    return Task { @MainActor in
      for _ in 0 ..< Self.maxPagesPerStep {
        await loadMore()
        guard stillShown(), postsFeed?.id == feed.id, router.fullPath == path, !showsModal, !Self.windowPresentsSomething() else { return }
        if adjacentPost(offset, in: router) != nil {
          openLoadedPost(offset, in: router)
          return
        }
        guard let id = Self.feedPostID(in: router), feed.target.posts?().contains(where: { $0.id == id }) == true,
              feed.target.canLoadMore?() == true else { return }
      }
    }
  }

  static let maxPagesPerStep = 3

  private func openLoadedPost(_ offset: Int, in router: Router) {
    guard let post = adjacentPost(offset, in: router) else { return }
    router.openAdjacentPost(.reddit(.post(post)))
    if let feed = postsFeed, targets.contains(where: { $0.id == feed.id }) {
      feed.target.reveal?(post)
    }
  }

  static func feedPostID(in router: Router) -> String? {
    guard let feedTop = router.feedPath.last ?? router.fullPath.first, listsPosts(feedTop), let post = router.postColumn.first,
          router.showsPostBesideFeed || router.postPath.isEmpty else { return nil }
    return post.id
  }

  private static func listsPosts(_ dest: Router.NavDest) -> Bool {
    if case .reddit(.user) = dest {
      return true
    }
    return dest.isFeed
  }

  static func post(_ offset: Int, from id: String, in posts: [Post]) -> Post? {
    guard let index = posts.firstIndex(where: { $0.id == id }) else { return nil }
    let target = index + offset
    return posts.indices.contains(target) ? posts[target] : nil
  }
}

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
      .onChange(of: target?.actions ?? []) {
        if let registration, let target {
          CommandTargets.shared.update(registration, to: target)
        }
      }
  }
}

extension View {
  func commandTarget(_ target: CommandTargets.Target?) -> some View {
    modifier(CommandTargetModifier(target: target, key: 0))
  }

  func commandTarget(_ target: CommandTargets.Target?, updatingWith key: some Equatable) -> some View {
    modifier(CommandTargetModifier(target: target, key: key))
  }

  func feedCommandTarget(_ target: CommandTargets.Target) -> some View {
    ScrollViewReader { proxy in
      commandTarget(target.revealing(with: proxy))
    }
  }
}
