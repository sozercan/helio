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
  @Environment(\.contentWidth) private var contentWidth
  @State private var ignoreSpecificComment = false
  @State private var hideElements = true
  @State private var sort: CommentSortOption
  @State private var commentsLoad = CommentsLoad()

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

  /// Reloads the post and its comments (pull to refresh, another sort).
  func asyncFetch() async {
    let request = await MainActor.run { commentsLoad.begin() }
    if let result = await post.refreshPost(commentID: ignoreSpecificComment ? nil : highlightID, sort: sort, subreddit: subreddit.data?.display_name ?? subreddit.id, full: true), let newComments = result.0 {
      newComments.forEach { $0.parentHelio = comments }
      let applied = await MainActor.run {
        // A later request (another sort) replaces these.
        guard commentsLoad.isCurrent(request) else { return false }
        comments = newComments
        return true
      }
      guard applied else { return }
      Task(priority: .utility) {
        await RedditAPI.shared.updateCommentsWithAvatar(comments: newComments, avatarSize: selectedTheme.comments.theme.badge.avatar.size)
      }

      Task(priority: .background) {
        if let numComments = post.data?.num_comments {
          await post.saveCommentsCount(numComments: numComments)
        }
      }
    }
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
              PostReplies(commentsLoad: commentsLoad, post: post, subreddit: subreddit, ignoreSpecificComment: ignoreSpecificComment, highlightID: highlightID, sort: sort, proxy: proxy, topVisibleCommentId: $topVisibleCommentId, previousScrollTarget: $previousScrollTarget, comments: $comments)
            }

            if !ignoreSpecificComment, highlightID != nil {
              Section {
                Button {
                  globalLoaderStart("Loading full post...")
                  withAnimation {
                    ignoreSpecificComment = true
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
        .relayoutPosts({ [post] }, contentWidth: contentWidth, theme: selectedTheme)
        .toolbar { Toolbar(hideElements: hideElements, subreddit: subreddit, post: post, sort: $sort) }
        .onChange(of: sort) { _ in
          updatePost()
        }
        .onAppear {
          doThisAfter(0.5) {
            hideElements = false
            doThisAfter(0.1) {
              if highlightID != nil {
                withAnimation { proxy.scrollTo("loading-comments") }
              }
            }
          }
          post.layoutIfNeeded(contentWidth: contentWidth)
          // Comments start loading now; they're shown once the push animation is over.
          if !commentsLoad.started {
            let full = post.data == nil
            let task = Task(priority: .userInitiated) {
              await post.refreshPost(commentID: highlightID, sort: sort, subreddit: subreddit.data?.display_name ?? subreddit.id, full: full)
            }
            commentsLoad.startPrefetch(CommentsLoad.Prefetch(task: task, sort: sort, commentID: highlightID))
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
          Spacer(minLength: 0)
          if !inlineActions {
            // At its natural width: squeezed, the score's ratio wraps.
            PostFloatingPill(post: post, subreddit: subreddit, showUpVoteRatio: defSettings.showUpVoteRatio)
              .fixedSize()
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
}

/// A post's comment requests: the first one, started when the post opens and picked up by
/// `PostReplies`, and the reloads after it. Only the latest request's comments are shown.
@MainActor
final class CommentsLoad {
  struct Prefetch {
    let task: Task<([Comment]?, String?)?, Never>
    let sort: CommentSortOption
    let commentID: String?
  }

  private(set) var started = false
  private var prefetch: Prefetch?
  private var generation = 0

  func startPrefetch(_ prefetch: Prefetch) {
    started = true
    self.prefetch = prefetch
  }

  /// The prefetch, if it asked for the same comments. Taken once.
  func takePrefetch(sort: CommentSortOption, commentID: String?) -> Task<([Comment]?, String?)?, Never>? {
    defer { prefetch = nil }
    guard let prefetch, prefetch.sort == sort, prefetch.commentID == commentID else { return nil }
    return prefetch.task
  }

  /// Starts a request. Its comments apply only while it's the latest: `isCurrent(request)`.
  func begin() -> Int {
    generation += 1
    return generation
  }

  func isCurrent(_ request: Int) -> Bool {
    request == generation
  }
}

private struct Toolbar: ToolbarContent {
  var hideElements: Bool
  var subreddit: Subreddit
  var post: Post
  @Binding var sort: CommentSortOption

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
          Nav.to(.reddit(.subInfo(subreddit)))
        } label: {
          SubredditIcon(subredditIconKit: data.subredditIconKit)
        }
        .accessibilityLabel("About r/\(data.display_name ?? subreddit.id)")
      }
    }
  }
}
