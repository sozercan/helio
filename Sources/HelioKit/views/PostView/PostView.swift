//
//  PostView.swift
//  Helio
//
//  Created by Igor Marcossi on 28/06/23.
//

import AlertToast
import AVFoundation
import Defaults
import SwiftUI

struct PostView: View, Equatable {
  static func == (lhs: PostView, rhs: PostView) -> Bool {
    lhs.post == rhs.post && lhs.subreddit.id == rhs.subreddit.id && lhs.hideElements == rhs.hideElements && lhs.ignoreSpecificComment == rhs.ignoreSpecificComment && lhs.sort == rhs.sort && lhs.comments.count == rhs.comments.count
  }

  var post: Post
  var subreddit: Subreddit
  var forceCollapse: Bool
  /// When true, this PostView is being rendered inside a non-interactive context-menu preview,
  /// so the floating pill (whose buttons can never receive taps there) is hidden.
  var isPreview: Bool
  var highlightID: String?
  @Default(.PostPageDefSettings) private var defSettings
  @Default(.CommentsSectionDefSettings) var commentsSectionDefSettings
  @Default(.CommentLinkDefSettings) private var commentLinkDefSettings
  @Environment(\.useTheme) private var selectedTheme
  @Environment(\.globalLoaderStart) private var globalLoaderStart
  @Environment(\.globalLoaderDismiss) private var globalLoaderDismiss
  @Environment(\.contentWidth) private var contentWidth
  @State private var ignoreSpecificComment = false
  @Environment(\.navColumn) private var navColumn
  @State private var hideElements = true
  @State private var sort: CommentSortOption
  @State private var commentsLoad = CommentsLoad()
  /// The comments seen before this visit (`PostReplies`).
  @State private var seenComments: String?
  /// The reply sheet opened by the menu bar's Reply; the post's bar has its own.
  @State private var showReplyModal = false

  @SilentState private var topVisibleCommentId: String? = nil
  @SilentState private var previousScrollTarget: String? = nil
  @State private var comments: [Comment] = []

  init(post: Post, subreddit: Subreddit, forceCollapse: Bool = false, isPreview: Bool = false, highlightID: String? = nil) {
    self.post = post
    self.subreddit = subreddit
    self.forceCollapse = forceCollapse
    self.isPreview = isPreview
    self.highlightID = highlightID

    let defSettings = CachedDefaults[.PostPageDefSettings]
    let commentsDefSettings = CachedDefaults[.CommentsSectionDefSettings]

    _sort = State(initialValue: defSettings.perPostSort ? (defSettings.postSorts[post.id] ?? commentsDefSettings.preferredSort) : commentsDefSettings.preferredSort)
  }

  /// Loads the comments, and with `full` the post's details. Every load (the first one, pull to
  /// refresh, another sort, the whole conversation, after a reply) goes through here, and the
  /// newest wins: one still in flight is ignored when it lands. With `proxy`, scrolls to the
  /// comment a link opened once they show. `savesCount: false` for the first load, which
  /// `onAppear` saves the comment count for already.
  func asyncFetch(full: Bool = true, savesCount: Bool = true, proxy: ScrollViewProxy? = nil) async {
    let request = commentsLoad.begin()
    let commentID = ignoreSpecificComment ? nil : highlightID
    // The post's details apply only while this is the newest load, like its comments.
    let result = await post.refreshPost(commentID: commentID, sort: sort, subreddit: subreddit.data?.display_name ?? subreddit.id, full: full, appliesDetails: { [commentsLoad] in commentsLoad.isCurrent(request) })
    guard commentsLoad.isCurrent(request) else { return }
    commentsLoad.finish()
    guard let result, let newComments = result.0 else { return }
    newComments.forEach { $0.parentHelio = comments }
    // Not animated: an animated insert makes the list build and measure every new row in one
    // long frame.
    comments = newComments
    Task(priority: .utility) {
      await RedditAPI.shared.updateCommentsWithAvatar(comments: newComments, avatarSize: selectedTheme.comments.theme.badge.avatar.size)
    }
    if savesCount {
      Task(priority: .background) {
        if let numComments = post.data?.num_comments {
          await post.saveCommentsCount(numComments: numComments)
        }
      }
    }
    // Before the push animation ends the comments aren't shown yet; `onAppear` scrolls then.
    if let proxy, !hideElements {
      doThisAfter(0.1) { scrollToHighlight(proxy) }
    }
  }

  /// Scrolls to the comment a link opened, if it's among the comments shown.
  @discardableResult
  func scrollToHighlight(_ proxy: ScrollViewProxy) -> Bool {
    guard var specificID = highlightID else { return false }
    specificID = specificID.hasPrefix("t1_") ? String(specificID.dropFirst(3)) : specificID
    guard let rowID = CommentTree.rows(for: comments).first(where: { $0.comment.data?.id == specificID })?.id else { return false }
    withAnimation(spring) {
      proxy.scrollTo(rowID, anchor: .center)
    }
    return true
  }

  /// The page is titled by its subreddit, with the comment count under it; the post's own
  /// title is the first thing on the page. Empty until the post loads.
  static func navigationTitles(_ data: PostData?) -> (title: String, subtitle: String) {
    guard let data else { return ("", "") }
    return (data.subreddit_name_prefixed, String(localized: "\(data.num_comments) comments"))
  }

  func updatePost() {
    Task(priority: .userInitiated) { await asyncFetch() }
  }

  var body: some View {
    let (navTitle, navSubtitle) = Self.navigationTitles(post.data)
    let commentsHPad = selectedTheme.comments.theme.outerHPadding > 0 ? selectedTheme.comments.theme.outerHPadding : selectedTheme.comments.theme.innerPadding.horizontal
    GeometryReader { geometryReader in
      ScrollViewReader { proxy in
        List {
          Group {
            Section {
              if let helioData = post.helioData {
                PostContent(post: post, helioData: helioData, forceCollapse: forceCollapse)
              }
              //              .equatable()

              if selectedTheme.posts.inlineFloatingPill, !isPreview {
                PostFloatingPill(post: post, subreddit: subreddit, showUpVoteRatio: defSettings.showUpVoteRatio)
                  .padding(-10)
              }

              Text("Comments")
                .fontSize(20, .bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id("comments-header")
                .listRowInsets(EdgeInsets(top: selectedTheme.posts.commentsDistance / 2, leading: commentsHPad, bottom: 8, trailing: commentsHPad))
            }
            .listRowBackground(Color.clear)

            if !hideElements {
              PostReplies(commentsLoad: commentsLoad, seenComments: seenComments, post: post, subreddit: subreddit, ignoreSpecificComment: ignoreSpecificComment, highlightID: highlightID, sort: sort, proxy: proxy, topVisibleCommentId: $topVisibleCommentId, previousScrollTarget: $previousScrollTarget, comments: $comments)
            }

            if !ignoreSpecificComment, highlightID != nil {
              Section {
                Button {
                  globalLoaderStart("Loading full post...")
                  withAnimation {
                    ignoreSpecificComment = true
                  }
                  withAnimation(spring) {
                    proxy.scrollTo("post-content", anchor: .bottom)
                  }
                  Task(priority: .userInitiated) {
                    // Keeps the comment the link opened in view, now among the whole thread.
                    // Just the comments of a loaded post: its details and media stay.
                    await asyncFetch(full: post.data == nil, proxy: proxy)
                    globalLoaderDismiss()
                  }
                } label: {
                  HStack {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                    Text("View full conversation")
                  }
                }
              }
              .listRowBackground(Color.primary.opacity(0.1))
            }
          }
          .listRowSeparator(.hidden)
        }
        .scrollIndicators(.never)
        .themedListBG(selectedTheme.posts.bg)
        .transition(.opacity)
        .environment(\.defaultMinListRowHeight, 1)
        .listStyle(.plain)
        .refreshable {
          await asyncFetch()
        }
        // A bar of its own, so the list makes room for it instead of hiding comments under it.
        .safeAreaBar(edge: .bottom) {
          if !isPreview {
            bottomBar(proxy: proxy)
          }
        }
        .navigationTitle(navTitle)
        .navigationSubtitle(navSubtitle)
        .navigationBarTitleDisplayMode(.inline)
        // Not `relayoutPosts`: the page lays its media out on its own (`Post.pageLayout`), and
        // relaying out the post would fight its feed row when the two are side by side.
        .toolbar { Toolbar(hideElements: hideElements, subreddit: subreddit, post: post, sort: $sort, column: navColumn) }
        .onChange(of: sort) { _ in
          updatePost()
        }
        .onAppear {
          doThisAfter(0.5) {
            hideElements = false
            doThisAfter(0.1) {
              if highlightID != nil, !scrollToHighlight(proxy) {
                withAnimation { proxy.scrollTo("loading-comments") }
              }
            }
          }
          post.layoutIfNeeded(contentWidth: contentWidth)
          // Comments start loading now; they're shown once the push animation is over.
          if !commentsLoad.started {
            // The comments seen before this visit, so the new ones stand out; the load saves
            // these as seen.
            seenComments = post.helioData?.seenComments
            Task(priority: .userInitiated) { await asyncFetch(full: post.data == nil, savesCount: false, proxy: proxy) }
          }

          Task(priority: .background) {
            if let numComments = post.data?.num_comments {
              await post.saveCommentsCount(numComments: numComments)
            }
          }

          Task(priority: .utility) {
            await subreddit.loadIfNeeded()
          }
        }
        // A context-menu preview isn't a screen the menu bar's commands act on.
        // Kept current when the page is handed a new Post for the same destination (after a refresh).
        .commandTarget(isPreview ? nil : CommandTargets.Target(kind: .post, column: navColumn, refresh: updatePost, post: post, reply: { showReplyModal = true }), updatingWith: ObjectIdentifier(post))
        .sheet(isPresented: $showReplyModal) {
          // Reloads the comments once the reply is posted, so it shows, and the post's details
          // with its comment count. A reply to the post is top level: reload the whole thread,
          // not just the comment a link opened it on.
          ReplyModalPost(post: post, updateComments: {
            ignoreSpecificComment = true
            updatePost()
          })
        }
        .onPreferenceChange(CommentUtils.AnchorsKey.self) { anchors in
          Task(priority: .background) {
            topVisibleCommentId = CommentUtils.shared.topCommentRow(of: anchors, in: geometryReader)
          }
        }
      }
    }
  }

  /// The post's actions and the jump to the next comment, on glass. The jump button sits on the
  /// left unless the actions are inline in the post and the setting puts it on the right.
  @ViewBuilder
  private func bottomBar(proxy: ScrollViewProxy) -> some View {
    let inlineActions = selectedTheme.posts.inlineFloatingPill
    let showSkipper = commentsSectionDefSettings.commentSkipper
    let skipperOnLeft = !inlineActions || commentLinkDefSettings.jumpNextCommentButtonLeft
    if showSkipper || !inlineActions {
      GlassEffectContainer(spacing: 12) {
        HStack(spacing: 12) {
          if showSkipper, skipperOnLeft {
            CommentSkipper(topVisibleCommentId: $topVisibleCommentId, previousScrollTarget: $previousScrollTarget, comments: comments, reader: proxy)
          }
          if inlineActions {
            // Only the skipper shows: keep it on its side.
            Spacer(minLength: 0)
          } else {
            // The pill at its natural width, since squeezed the score's ratio wraps. When that
            // doesn't fit the room left beside the skipper (narrow windows, large text), drop
            // the ratio, then fold the actions into a menu.
            ViewThatFits(in: .horizontal) {
              pill(showRatio: defSettings.showUpVoteRatio, compact: false)
              if defSettings.showUpVoteRatio {
                pill(showRatio: false, compact: false)
              }
              pill(showRatio: false, compact: true)
            }
            // Takes the room the skipper leaves, so the choice above is measured against all of it.
            .frame(maxWidth: .infinity, alignment: .trailing)
          }
          if showSkipper, !skipperOnLeft {
            CommentSkipper(topVisibleCommentId: $topVisibleCommentId, previousScrollTarget: $previousScrollTarget, comments: comments, reader: proxy)
          }
        }
      }
      .padding(.horizontal, 12)
      .padding(.bottom, 8)
    }
  }

  private func pill(showRatio: Bool, compact: Bool) -> some View {
    PostFloatingPill(post: post, subreddit: subreddit, showUpVoteRatio: showRatio, compact: compact)
      .fixedSize()
  }
}

/// A post's comment requests: the first one, started when the post opens, and the reloads after
/// it. Only the latest request's comments are shown, and only it ends the loading state.
@MainActor
@Observable
final class CommentsLoad {
  private(set) var started = false
  /// The first comments came, or the request for them failed: the list shows them, or that
  /// there are none, instead of its spinner.
  private(set) var loaded = false
  @ObservationIgnored private var generation = 0

  /// Starts a request. Its comments apply only while it's the latest: `isCurrent(request)`.
  func begin() -> Int {
    started = true
    generation += 1
    return generation
  }

  func isCurrent(_ request: Int) -> Bool {
    request == generation
  }

  /// The latest request finished.
  func finish() {
    loaded = true
  }
}

private struct Toolbar: ToolbarContent {
  var hideElements: Bool
  var subreddit: Subreddit
  var post: Post
  @Binding var sort: CommentSortOption
  /// The column the post is in, where its subreddit's info opens.
  var column: Router.Column?

  var body: some ToolbarContent {
    ToolbarItem(id: "postview-sort", placement: .topBarTrailing) {
      Menu {
        if !hideElements {
          Picker("Sort comments", selection: Binding(get: { sort }, set: { opt in
            sort = opt
            Defaults[.PostPageDefSettings].postSorts[post.id] = opt
          })) {
            ForEach(CommentSortOption.allCases) { opt in
              Label(opt.rawVal.value.capitalized, systemImage: opt.rawVal.icon)
                .tag(opt)
            }
          }
        }
      } label: {
        Label("Sort", systemImage: sort.rawVal.icon)
      }
      .animation(nil, value: sort)
    }

    if let data = subreddit.data, !feedsAndSuch.contains(subreddit.id) {
      ToolbarSpacer(.fixed, placement: .topBarTrailing)

      ToolbarItem(id: "postview-sub", placement: .topBarTrailing) {
        Button {
          Nav.to(.reddit(.subInfo(subreddit)), from: column)
        } label: {
          SubredditIcon(subredditIconKit: data.subredditIconKit)
        }
        .accessibilityLabel("About r/\(data.display_name ?? subreddit.id)")
      }
    }
  }
}
