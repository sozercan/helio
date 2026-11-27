import AlertToast
import AVFoundation
import Defaults
import SwiftUI

struct PostView: View, Equatable {
  static func == (lhs: PostView, rhs: PostView) -> Bool {
    lhs.post == rhs.post && lhs.subreddit.id == rhs.subreddit.id
  }

  var post: Post
  var subreddit: Subreddit
  var forceCollapse: Bool
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

  @State private var showReplyModal = false
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

  func asyncFetch(full: Bool = true, savesCount: Bool = true, proxy: ScrollViewProxy? = nil) async {
    let request = commentsLoad.begin()
    let commentID = ignoreSpecificComment ? nil : highlightID
    let result = await post.refreshPost(commentID: commentID, sort: sort, subreddit: subreddit.data?.display_name ?? subreddit.id, full: full, appliesDetails: { [commentsLoad] in commentsLoad.isCurrent(request) })
    guard commentsLoad.isCurrent(request) else { return }
    guard let result, let newComments = result.0 else {
      commentsLoad.finish(failed: true)
      return
    }
    commentsLoad.finish(failed: false)
    newComments.forEach { $0.parentHelio = comments }
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
    if let proxy, !hideElements {
      doThisAfter(0.1) { scrollToHighlight(proxy) }
    }
  }

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
              PostReplies(commentsLoad: commentsLoad, seenComments: seenComments, post: post, subreddit: subreddit, ignoreSpecificComment: ignoreSpecificComment, highlightID: highlightID, sort: sort, proxy: proxy, topVisibleCommentId: Bindable(session).topVisibleCommentId, previousScrollTarget: Bindable(session).previousScrollTarget, comments: Bindable(session).comments, session: session, retry: {
                Task(priority: .userInitiated) {
                  await asyncFetch(full: post.data == nil, proxy: proxy)
                }
              })
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
        .safeAreaBar(edge: .bottom) {
          if !isPreview {
            bottomBar(proxy: proxy)
          }
        }
        .navigationTitle(navTitle)
        .navigationSubtitle(navSubtitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Toolbar(hideElements: hideElements, subreddit: subreddit, post: post, sort: Bindable(session).sort, column: navColumn) }
        .onChange(of: sort) { _ in
          updatePost()
        }
        .onChange(of: commentsLoad.loaded) { _, loaded in
          guard loaded, awaitsHighlight, !hideElements else { return }
          awaitsHighlight = false
          doThisAfter(0.1) { scrollToHighlight(proxy) }
        }
        .onScrollPhaseChange { _, phase in
          if phase == .interacting {
            session.readerScrolled()
          } else if phase == .idle {
            session.saveScrollAnchor()
          }
        }
        .onAppear {
          lease.adopt(in: screenStateScope)
          let handedOver = lease.takeHandedOver()
          let anchor = handedOver ? session.scrollAnchorRowID() : nil
          if handedOver, !hideElements, anchor != nil || session.scrolled {
            if let anchor {
              doThisAfter(0.1) { proxy.scrollTo(anchor, anchor: .top) }
            }
          } else {
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
          if !commentsLoad.started {
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
        .commandTarget(isPreview ? nil : CommandTargets.Target(kind: .post, column: navColumn, refresh: updatePost, post: post, reply: { showReplyModal = true }, actions: actions), updatingWith: ObjectIdentifier(post))
        .sheet(isPresented: $showReplyModal) {
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

  private var actions: [ScreenAction] {
    var actions: [ScreenAction] = []
    if !hideElements {
      actions.append(.sortComments(sort) { opt in
        sort = opt
        Defaults[.PostPageDefSettings].postSorts[post.id] = opt
      })
    }
    if subreddit.data != nil, !feedsAndSuch.contains(subreddit.id) {
      actions.append(.subredditInfo(subreddit, column: navColumn))
    }
    return actions
  }

  @ViewBuilder
  private func bottomBar(proxy: ScrollViewProxy) -> some View {
    let inlineActions = selectedTheme.posts.inlineFloatingPill
    let showSkipper = commentsSectionDefSettings.commentSkipper
    let skipperOnLeft = !inlineActions || commentLinkDefSettings.jumpNextCommentButtonLeft
    let activeUsername = RedditCredentialsManager.shared.selectedCredential?.userName
    if showSkipper || !inlineActions {
      GlassEffectContainer(spacing: 12) {
        HStack(spacing: 12) {
          if showSkipper, skipperOnLeft {
            CommentSkipper(
              topVisibleCommentId: Bindable(session).topVisibleCommentId,
              previousScrollTarget: Bindable(session).previousScrollTarget,
              comments: comments,
              seenComments: seenComments,
              activeUsername: activeUsername,
              reader: proxy,
            )
          }
          if inlineActions {
            Spacer(minLength: 0)
          } else {
            ViewThatFits(in: .horizontal) {
              pill(showRatio: defSettings.showUpVoteRatio, compact: false)
              if defSettings.showUpVoteRatio {
                pill(showRatio: false, compact: false)
              }
              pill(showRatio: false, compact: true)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
          }
          if showSkipper, !skipperOnLeft {
            CommentSkipper(
              topVisibleCommentId: Bindable(session).topVisibleCommentId,
              previousScrollTarget: Bindable(session).previousScrollTarget,
              comments: comments,
              seenComments: seenComments,
              activeUsername: activeUsername,
              reader: proxy,
            )
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

@MainActor
@Observable
final class PostSession {
  var sort: CommentSortOption
  let commentsLoad = CommentsLoad()
  var comments: [Comment] = []
  var seenComments: String?
  var ignoreSpecificComment = false
  var hideElements = true
  @ObservationIgnored var topVisibleCommentId: String?
  @ObservationIgnored var previousScrollTarget: String?
  @ObservationIgnored private var shownRowIDs: [String: Int] = [:]
  @ObservationIgnored private var savedRowIDs: Set<String> = []
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

  func readerScrolled() {
    scrolled = true
  }

  func saveScrollAnchor() {
    savedRowIDs = Set(shownRowIDs.keys)
  }

  func scrollAnchorRowID() -> String? {
    guard !savedRowIDs.isEmpty else { return nil }
    return CommentTree.rows(for: comments).first { savedRowIDs.contains($0.id) }?.id
  }
}

@MainActor
@Observable
final class CommentsLoad {
  private(set) var started = false
  private(set) var loaded = false
  private(set) var failed = false
  @ObservationIgnored private var generation = 0

  func begin() -> Int {
    started = true
    if failed {
      loaded = false
    }
    failed = false
    generation += 1
    return generation
  }

  func isCurrent(_ request: Int) -> Bool {
    request == generation
  }

  func finish(failed: Bool = false) {
    self.failed = failed
    loaded = true
  }
}

private struct Toolbar: ToolbarContent {
  var hideElements: Bool
  var subreddit: Subreddit
  var post: Post
  @Binding var sort: CommentSortOption
  var column: Router.Column?

  var body: some ToolbarContent {
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
