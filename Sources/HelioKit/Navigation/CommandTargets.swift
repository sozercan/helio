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
    enum Kind { case feed, post, subs, search }

    var kind: Kind
    /// The posts split view's column it shows in.
    var column: Router.Column?
    var refresh: (() -> Void)?
    var focusSearch: (() -> Void)?
    /// A feed's posts, in order, for Next and Previous Post.
    var posts: (() -> [Post])?
    /// Scrolls a feed to one of its posts.
    var reveal: ((Post) -> Void)?
    /// The post a post screen shows, for voting and replying.
    var post: Post?
    var reply: (() -> Void)?

    func revealing(with proxy: ScrollViewProxy) -> Target {
      var target = self
      target.reveal = { post in withAnimation { proxy.scrollTo(post.id) } }
      return target
    }
  }

  private(set) var targets: [(id: UUID, target: Target)] = []

  /// Set by Find when no search field shows: the Search tab focuses its field when it next appears.
  @ObservationIgnored var searchFocusPending = false

  func register(_ target: Target) -> UUID {
    let id = UUID()
    targets.append((id, target))
    return id
  }

  func unregister(_ id: UUID) {
    targets.removeAll { $0.id == id }
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

  var canRefresh: Bool {
    refreshTarget != nil
  }

  func refresh() {
    refreshTarget?.refresh?()
  }

  /// Focuses the search field shown last, else switches to the Search tab and focuses its.
  func find(nav: Nav = .shared) {
    if let focus = targets.last(where: { $0.target.focusSearch != nil })?.target.focusSearch {
      focus()
    } else {
      searchFocusPending = true
      // On the Search tab already, this also closes the screens opened from it.
      nav.activeTab = .search
    }
  }

  /// The post shown last, for voting and replying.
  var openPost: Target? {
    targets.last { $0.target.kind == .post && $0.target.post != nil }?.target
  }

  /// The posts tab's feed column, for Next and Previous Post: the feed shown last there.
  private var feedColumn: Target? {
    targets.last { $0.target.kind == .feed && $0.target.column == .feed && $0.target.posts != nil }?.target
  }

  /// The post `offset` places from the one open in the posts tab's post column, in the feed
  /// beside it. Nil when no post from that feed is open, or at its end.
  func adjacentPost(_ offset: Int, nav: Nav = .shared) -> Post? {
    guard nav.activeTab == .posts, let feed = feedColumn, let posts = feed.posts?(),
          case let .reddit(dest) = nav[.posts].postColumn.first else { return nil }
    return Self.post(offset, from: dest.id, in: posts)
  }

  /// Opens the post `offset` places from the open one in the post column and scrolls the feed to it.
  func openAdjacentPost(_ offset: Int, nav: Nav = .shared) {
    guard let post = adjacentPost(offset, nav: nav) else { return }
    nav[.posts].navigateTo(.reddit(.post(post)), from: .feed)
    feedColumn?.reveal?(post)
  }

  /// The post `offset` places from the one with `id` in `posts`.
  static func post(_ offset: Int, from id: String, in posts: [Post]) -> Post? {
    guard let index = posts.firstIndex(where: { $0.id == id }) else { return nil }
    let target = index + offset
    return posts.indices.contains(target) ? posts[target] : nil
  }
}

private struct CommandTargetModifier: ViewModifier {
  var target: CommandTargets.Target?
  @State private var registration: UUID?

  func body(content: Content) -> some View {
    content
      .onAppear {
        guard registration == nil, let target else { return }
        registration = CommandTargets.shared.register(target)
      }
      .onDisappear {
        if let registration {
          CommandTargets.shared.unregister(registration)
        }
        registration = nil
      }
  }
}

extension View {
  /// Makes this screen what the menu bar's commands act on while it shows. Nil registers nothing.
  func commandTarget(_ target: CommandTargets.Target?) -> some View {
    modifier(CommandTargetModifier(target: target))
  }

  /// `commandTarget` for a feed, which Next and Previous Post scroll to the post they open.
  func feedCommandTarget(_ target: CommandTargets.Target) -> some View {
    ScrollViewReader { proxy in
      commandTarget(target.revealing(with: proxy))
    }
  }
}
