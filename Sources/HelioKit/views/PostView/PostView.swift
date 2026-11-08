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
    // Not the comments and their sort: those are in the observed session, whose changes update
    // the page themselves.
    lhs.post == rhs.post && lhs.subreddit.id == rhs.subreddit.id
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
  @Environment(\.navColumn) private var navColumn
  @Environment(\.screenStateScope) private var screenStateScope
  /// The comments and how they're shown, taken over from the screen this one replaces when the
  /// layout changes (`ScreenStates`).
  @State private var lease: ScreenStateLease<PostSession>
  private var session: PostSession {
    lease.model
  }

  private var ignoreSpecificComment: Bool {
    get { session.ignoreSpecificComment }
    nonmutating set { session.ignoreSpecificComment = newValue }
  }

  private var hideElements: Bool {
    get { session.hideElements }
    nonmutating set { session.hideElements = newValue }
  }

  private var sort: CommentSortOption {
    get { session.sort }
    nonmutating set { session.sort = newValue }
  }

  private var commentsLoad: CommentsLoad {
    session.commentsLoad
  }

  private var seenComments: String? {
    get { session.seenComments }
    nonmutating set { session.seenComments = newValue }
  }

  private var topVisibleCommentId: String? {
    get { session.topVisibleCommentId }
    nonmutating set { session.topVisibleCommentId = newValue }
  }

  private var comments: [Comment] {
    get { session.comments }
    nonmutating set { session.comments = newValue }
  }

  /// The reply sheet opened by the menu bar's Reply; the post's bar has its own.
  @State private var showReplyModal = false
  /// This page's stay, timed for For You's reading history (`ForYouHistory`).
  @State private var forYouVisit: UUID?
  /// Scrolls to the comment a link opened once the comments come: taken over from a screen that
  /// was loading them.
  @State private var awaitsHighlight = false

  init(post: Post, subreddit: Subreddit, forceCollapse: Bool = false, isPreview: Bool = false, highlightID: String? = nil) {
    self.post = post
    self.subreddit = subreddit
    self.forceCollapse = forceCollapse
    self.isPreview = isPreview
    self.highlightID = highlightID

    let defSettings = CachedDefaults[.PostPageDefSettings]
    let commentsDefSettings = CachedDefaults[.CommentsSectionDefSettings]

    let sort = defSettings.perPostSort ? (defSettings.postSorts[post.id] ?? commentsDefSettings.preferredSort) : commentsDefSettings.preferredSort
    _lease = State(initialValue: isPreview ? ScreenStateLease(unshared: PostSession(sort: sort)) : ScreenStates.shared.lease("post|\(highlightID ?? "")", owner: post) { PostSession(sort: sort) })
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
              PostReplies(commentsLoad: commentsLoad, seenComments: seenComments, post: post, subreddit: subreddit, ignoreSpecificComment: ignoreSpecificComment, highlightID: highlightID, sort: sort, proxy: proxy, topVisibleCommentId: Bindable(session).topVisibleCommentId, previousScrollTarget: Bindable(session).previousScrollTarget, comments: Bindable(session).comments, session: session)
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
        .touchScrollIndicators(.never)
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
        .toolbar { Toolbar(hideElements: hideElements, subreddit: subreddit, post: post, sort: Bindable(session).sort, column: navColumn) }
        .onChange(of: sort) { _ in
          updatePost()
        }
        .onChange(of: commentsLoad.loaded) { _, loaded in
          // While the comments are hidden, the scroll once they show does it.
          guard loaded, awaitsHighlight, !hideElements else { return }
          awaitsHighlight = false
          doThisAfter(0.1) { scrollToHighlight(proxy) }
        }
        // Where it's back to after the layout changes.
        .onScrollPhaseChange { _, phase in
          if phase == .interacting {
            session.readerScrolled()
          } else if phase == .idle {
            session.saveScrollAnchor()
          }
        }
        .onAppear {
          if !isPreview, forYouVisit == nil {
            forYouVisit = ForYouHistory.began(post)
          }
          lease.adopt(in: screenStateScope)
          // Taken over from the screen this one replaced: back to where the reader left that one,
          // a comment row or the post's top, rather than to the comment a link opened.
          // A saved row however the list got there, the reader's scrolling or a jump to a comment;
          // the post's top only if the reader scrolled there.
          let handedOver = lease.takeHandedOver()
          let anchor = handedOver ? session.scrollAnchorRowID() : nil
          if handedOver, !hideElements, anchor != nil || session.scrolled {
            if let anchor {
              doThisAfter(0.1) { proxy.scrollTo(anchor, anchor: .top) }
            }
          } else {
            // The comments the old screen is still loading would scroll its own list to the one a
            // link opened once they come; this one does instead.
            if handedOver, highlightID != nil, !commentsLoad.loaded {
              awaitsHighlight = true
            }
            doThisAfter(0.5) {
              hideElements = false
              doThisAfter(0.1) {
                if highlightID != nil, !scrollToHighlight(proxy) {
                  withAnimation { proxy.scrollTo("loading-comments") }
                }
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
        .onDisappear {
          if let forYouVisit {
            ForYouHistory.ended(forYouVisit, post: post)
            self.forYouVisit = nil
          }
        }
        // A context-menu preview isn't a screen the menu bar's commands act on.
        // Kept current when the page is handed a new Post for the same destination (after a refresh).
        .commandTarget(isPreview ? nil : CommandTargets.Target(kind: .post, column: navColumn, refresh: updatePost, post: post, reply: { showReplyModal = true }, actions: actions), updatingWith: ObjectIdentifier(post))
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

  /// The comment sort and the subreddit's info, as in the navigation bar.
  private var actions: [ScreenAction] {
    var actions: [ScreenAction] = []
    // Like the navigation bar's picker, not before the comments start loading: a sort chosen
    // in that moment would start a second request for them.
    if !hideElements {
      actions.append(.sortComments(sort) { opt in
        sort = opt
        Defaults[.PostPageDefSettings].postSorts[post.id] = opt
      })
    }
    if subreddit.data != nil, !feedsAndSuch.contains(subreddit.id) {
      // From the column the post is in, like the navigation bar's button: a post at the feed
      // column's root opens it there.
      actions.append(.subredditInfo(subreddit, column: navColumn))
    }
    return actions
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
            CommentSkipper(topVisibleCommentId: Bindable(session).topVisibleCommentId, previousScrollTarget: Bindable(session).previousScrollTarget, comments: comments, reader: proxy)
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
            CommentSkipper(topVisibleCommentId: Bindable(session).topVisibleCommentId, previousScrollTarget: Bindable(session).previousScrollTarget, comments: comments, reader: proxy)
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

/// A post page's comments and how they're shown, kept apart from the page so a page built for
/// another layout takes them over (`ScreenStates`).
@MainActor
@Observable
final class PostSession {
  var sort: CommentSortOption
  let commentsLoad = CommentsLoad()
  var comments: [Comment] = []
  /// The comments seen before this visit (`PostReplies`).
  var seenComments: String?
  var ignoreSpecificComment = false
  /// Until the push animation ends.
  var hideElements = true
  /// The comment at the top of the list, which the comment skipper jumps from.
  @ObservationIgnored var topVisibleCommentId: String?
  @ObservationIgnored var previousScrollTarget: String?
  /// The comment rows the list shows: the topmost, reply or not, is where the page goes back to
  /// after the layout changes.
  /// Counted, as the old screen's list and the new one's share it while the layout changes.
  @ObservationIgnored private var shownRowIDs: [String: Int] = [:]
  /// The rows the list showed when it last stopped scrolling.
  @ObservationIgnored private var savedRowIDs: Set<String> = []
  /// The reader scrolled the list: no anchor then means the post's top, not a page still to
  /// scroll to the comment a link opened. Not the page's own scrolls, such as to the comments
  /// loading.
  @ObservationIgnored private(set) var scrolled = false

  init(sort: CommentSortOption) {
    self.sort = sort
  }

  func rowShown(_ id: String) {
    shownRowIDs[id, default: 0] += 1
  }

  func rowHidden(_ id: String) {
    if let count = shownRowIDs[id], count > 1 {
      shownRowIDs[id] = count - 1
    } else {
      shownRowIDs[id] = nil
    }
  }

  /// Saved when the list stops scrolling, not as rows go: the list hides all its rows when a
  /// screen covers it. Nil while no comment shows, as at the post's top.
  func readerScrolled() {
    scrolled = true
  }

  /// Only which rows showed: the topmost of them is found once, when a fold needs it, rather than
  /// flattening the whole thread each time the list stops.
  func saveScrollAnchor() {
    savedRowIDs = Set(shownRowIDs.keys)
  }

  /// The row at the top of the list when it last stopped scrolling. Nil while no comment showed,
  /// as at the post's top.
  func scrollAnchorRowID() -> String? {
    guard !savedRowIDs.isEmpty else { return nil }
    return CommentTree.rows(for: comments).first { savedRowIDs.contains($0.id) }?.id
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
    // On Mac these are in the window toolbar (`PostView.actions`).
    if ScreenAction.showsInNavigationBar {
      items
    }
  }

  @ToolbarContentBuilder
  private var items: some ToolbarContent {
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
