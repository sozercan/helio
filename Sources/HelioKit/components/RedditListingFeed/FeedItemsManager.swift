//
//  FeedItemsManager.swift
//  Helio
//
//  Created by Igor Marcossi on 26/01/24.
//

import Defaults
import Nuke
import SwiftUI

@MainActor
@Observable
class FeedItemsManager<S> {
  struct FetchContext {
    let limit: Int
    let credential: RedditCredential
  }

  typealias ItemsFetchFn = @MainActor (_ lastElementId: String?, _ sorting: S?, _ searchQuery: String?, _ flair: String?, _ context: FetchContext) async -> (entities: [RedditEntityType]?, after: String?)?

  /// `onlyReadPosts`: paging stopped after several pages in a row held only hidden read posts.
  enum DisplayMode: String { case loading, empty, items, endOfFeed, error, onlyReadPosts }

  @ObservationIgnored private var currentTask: Task<Void, Never>?
  @ObservationIgnored private var currentRequestID: UUID?
  @ObservationIgnored private var currentTaskIsReload = false
  @ObservationIgnored private var loadMoreHeldBack = false
  @ObservationIgnored private var listRequest: Request?

  /// One immutable query for the whole page chain, including pages hidden as already read.
  private struct Request {
    let sorting: S?
    let searchQuery: String?
    let flair: String?
    let chunkSize: Int
    let credential: RedditCredential?
    var authorization: RedditCredential.AuthorizationID? {
      credential?.authorizationID
    }
  }

  /// Set once the feed starts loading its first page.
  @ObservationIgnored private(set) var initialLoadStarted = false
  private(set) var displayMode: DisplayMode = .loading
  private(set) var isLoadingMore = false
  @ObservationIgnored private var failedLoadingMore = false
  private(set) var entities: [RedditEntityType] = [] {
    didSet { indexByID = Dictionary(entities.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first }) }
  }

  /// Rows look their position up as they appear; searching `entities` for each was quadratic.
  @ObservationIgnored private var indexByID: [String: Int] = [:]
  private var loadedEntitiesIds: Set<String> = []
  private(set) var lastElementId: String?
  var sorting: S?

  var searchQuery = Debouncer("")
  var selectedFilter: ShallowCachedFilter?

  var chunkSize: Int
  @ObservationIgnored private var fetchFn: ItemsFetchFn
  private let currentCredential: @MainActor () -> RedditCredential?
  @ObservationIgnored private var authorization: RedditCredential.AuthorizationID?
  private let prefetchRange = 2
  /// Whether this feed drops already-read posts when "Hide read posts" is on.
  private let hideReadPosts: Bool
  /// Pages fetched in a row whose posts were all hidden, before giving up.
  private let maxHiddenPagesInARow = 5

  init(sorting: S?, hideReadPosts: Bool = false, currentCredential: @escaping @MainActor () -> RedditCredential? = { RedditCredentialsManager.shared.selectedCredential }, fetchFn: @escaping ItemsFetchFn) {
    self.sorting = sorting
    self.hideReadPosts = hideReadPosts
    self.fetchFn = fetchFn
    self.currentCredential = currentCredential
    self.chunkSize = Defaults[.SubredditFeedDefSettings].chunkLoadSize
  }

  func loadIfNeeded() async {
    guard !initialLoadStarted else { return }
    await reload()
  }

  func reload(clearItems: Bool = false) async {
    guard !Task.isCancelled else { return }
    await startFetch(loadingMore: false, clearItems: clearItems)?.value
  }

  /// Whether `loadMore()` has a next page to load.
  /// Whether `loadMore()` has a next page to fetch: also after paging stopped on pages of only
  /// hidden read posts, as the feed's own "keep looking" does, so Next Post can go on.
  var canLoadMore: Bool {
    lastElementId != nil && (displayMode == .items || displayMode == .onlyReadPosts)
  }

  func loadMore() async {
    await fetchCaller(loadingMore: true)
  }

  func retry() async {
    await fetchCaller(loadingMore: failedLoadingMore)
  }

  private func fetchCaller(loadingMore: Bool) async {
    // A row task can be cancelled by a refresh before it ever starts running.
    guard !Task.isCancelled else { return }
    await startFetch(loadingMore: loadingMore)?.value
  }

  /// Reserve the request synchronously, so rows appearing together share one page fetch.
  private func startFetch(loadingMore: Bool, clearItems: Bool = false) -> Task<Void, Never>? {
    let credential = currentCredential()
    let currentAuthorization = credential?.authorizationID
    let accountChanged = initialLoadStarted && authorization != currentAuthorization
    let paging = loadingMore && !accountChanged
    if paging {
      if let currentTask {
        // The still-visible rows will not appear again if the refresh returns
        // the same posts. Carry their paging intent over to its replacement list.
        if currentTaskIsReload, !entities.isEmpty {
          loadMoreHeldBack = true
        }
        return currentTask
      }
      guard lastElementId != nil, displayMode == .items || displayMode == .onlyReadPosts || displayMode == .error else { return nil }
    } else {
      if clearItems || accountChanged {
        loadMoreHeldBack = false
        listRequest = nil
      } else if currentTask != nil, !currentTaskIsReload {
        loadMoreHeldBack = true
      }
      currentTask?.cancel()
    }

    initialLoadStarted = true
    isLoadingMore = paging
    if clearItems || accountChanged {
      entities = []
      loadedEntitiesIds = []
      lastElementId = nil
    }
    // A non-clearing refresh keeps the displayed rows mounted until replacement.
    withAnimation { displayMode = paging || !entities.isEmpty ? .items : .loading }
    let requestID = UUID()
    currentRequestID = requestID
    let request = if paging, let listRequest {
      // The cursor belongs to the displayed list's query, not settings for a
      // reload that has not started yet. Each new chain adopts the current limit.
      Request(sorting: listRequest.sorting, searchQuery: listRequest.searchQuery, flair: listRequest.flair, chunkSize: chunkSize, credential: credential)
    } else {
      Request(
        sorting: sorting,
        searchQuery: selectedFilter?.type == .custom ? selectedFilter?.text : searchQuery.debounced.isEmpty ? nil : searchQuery.debounced,
        flair: selectedFilter?.type != .custom ? selectedFilter?.text : nil,
        chunkSize: chunkSize,
        credential: credential,
      )
    }
    authorization = currentAuthorization
    let after = paging ? lastElementId : nil
    let task = Task {
      await self.fetchPage(loadingMore: paging, after: after, hiddenPagesInARow: 0, request: request, requestID: requestID)
      // A superseded task must not release a newer request's reservation.
      if self.currentRequestID == requestID {
        self.currentTask = nil
        self.currentRequestID = nil
        self.currentTaskIsReload = false
        self.isLoadingMore = false
        if !paging, self.displayMode != .error {
          let resumePaging = self.loadMoreHeldBack
          self.loadMoreHeldBack = false
          if resumePaging, self.displayMode == .items, self.currentCredential()?.authorizationID == request.authorization, !Task.isCancelled {
            await self.startFetch(loadingMore: true)?.value
          }
        }
      }
    }
    currentTaskIsReload = !paging
    currentTask = task
    return task
  }

  private func fetchPage(loadingMore: Bool, after lastElementId: String?, hiddenPagesInARow: Int, request: Request, requestID: UUID) async {
    guard currentRequestID == requestID, !Task.isCancelled, currentCredential()?.authorizationID == request.authorization else { return }
    // A captured signed-out state must not resolve whatever account is selected later.
    guard let credential = request.credential else {
      failedLoadingMore = loadingMore
      withAnimation { displayMode = .error }
      return
    }
    let result = await fetchFn(lastElementId, request.sorting, request.searchQuery, request.flair, FetchContext(limit: request.chunkSize, credential: credential))
    // Cancellation is cooperative: a network callback may still return data or an error.
    guard currentRequestID == requestID, !Task.isCancelled, currentCredential()?.authorizationID == request.authorization else { return }
    guard let (fetchedEntities, after) = result, let fetchedEntities else {
      failedLoadingMore = loadingMore
      withAnimation { displayMode = .error }
      return
    }

    // Without a cursor, the next fetch would start over from the first page.
    // Reddit can return short pages and lossy decoding can skip individual
    // children. A nonempty page with a cursor is still pageable.
    let reachedEnd = after == nil || fetchedEntities.isEmpty
    let shownEntities = withoutReadPosts(fetchedEntities)
    let onlyReadPosts = shownEntities.isEmpty && !fetchedEntities.isEmpty && !reachedEnd
    let skipPage = onlyReadPosts && hiddenPagesInARow < maxHiddenPagesInARow
    let gaveUp = onlyReadPosts && !skipPage

    if !loadingMore {
      listRequest = request
      withAnimation {
        displayMode = skipPage ? .items : gaveUp ? .onlyReadPosts : shownEntities.isEmpty ? .empty : reachedEnd ? .endOfFeed : .items
        entities = shownEntities
        self.lastElementId = after
        loadedEntitiesIds = Set(shownEntities.map(\.fullname))
      }
    } else {
      var newLoadedEntitiesIds = loadedEntitiesIds
      var newEntities = entities
      for entity in shownEntities where newLoadedEntitiesIds.insert(entity.fullname).inserted {
        newEntities.append(entity)
      }
      // Don't animate appending: it causes scroll jumps and builds every new row in one frame.
      displayMode = reachedEnd ? .endOfFeed : gaveUp ? .onlyReadPosts : .items
      entities = newEntities
      self.lastElementId = after
      loadedEntitiesIds = newLoadedEntitiesIds
    }

    if skipPage {
      isLoadingMore = true
      await fetchPage(loadingMore: true, after: after, hiddenPagesInARow: hiddenPagesInARow + 1, request: request, requestID: requestID)
    }
  }

  private func withoutReadPosts(_ entities: [RedditEntityType]) -> [RedditEntityType] {
    guard hideReadPosts, CachedDefaults[.PostLinkDefSettings].hideOnRead else { return entities }
    return entities.filter { entity in
      if case let .post(post) = entity {
        return !(post.data?.helioSeen ?? false)
      }
      return true
    }
  }

  /// Loads the next page near the end, and prefetches the media of the rows around `entity`
  /// unless `prefetchMedia` is off (the canvas loads only the thumbnails on screen).
  /// On the main actor, like the rows calling it: rows appearing together must not each start
  /// loading the next page.
  func elementAppeared(entity: RedditEntityType, prefetchMedia: Bool = true) {
    guard let index = indexByID[entity.id] else { return }
    if !entities.isEmpty, index >= entities.count - 7 {
      if currentTask != nil, currentTaskIsReload {
        loadMoreHeldBack = true
      } else if displayMode == .items, currentTask == nil {
        startFetch(loadingMore: true)
      }
    }
    guard prefetchMedia else { return }

    let start = index - prefetchRange < 0 ? 0 : index - prefetchRange
    let end = index + (prefetchRange + 1) > entities.count ? entities.count : index + (prefetchRange + 1)
    let toPrefetch = start < end ? Array(entities[start ..< end]) : []
    let reqs = getImgReqsFrom(toPrefetch)

    Post.prefetcher.startPrefetching(with: reqs)
  }

  /// The rows the list shows, by id: the topmost is where the feed goes back to after the
  /// layout changes (`ScreenStates`).
  /// Counted, as the old screen's list and the new one's share it while the layout changes.
  @ObservationIgnored private var shownRowIDs: [String: Int] = [:]
  /// The row at the top of the list when it last stopped scrolling; nil at the top of the feed.
  @ObservationIgnored private(set) var scrollAnchorID: String?
  /// The post the lightbox shows, for the feed to scroll to behind it.
  var revealRequest: FeedRevealRequest?

  /// Fetches through `fetchFn` from now on: the screen that took this feed over when the layout
  /// changed, as the one that made it is gone (`ScreenStates`).
  func replaceFetch(_ fetchFn: @escaping ItemsFetchFn) {
    self.fetchFn = fetchFn
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
  /// screen covers it, which would leave its last row as the top.
  func saveScrollAnchor() {
    let top = shownRowIDs.keys.compactMap { id in indexByID[id].map { (id, $0) } }.min { $0.1 < $1.1 }
    scrollAnchorID = top.flatMap { $0.1 == 0 ? nil : $0.0 }
  }

  func elementDisappeared(entity: RedditEntityType) {
    let reqs = getImgReqsFrom([entity])
    Post.prefetcher.stopPrefetching(with: reqs)
  }

  private func getImgReqsFrom(_ entities: [RedditEntityType]) -> [ImageRequest] {
    entities.reduce([] as [ImageRequest]) { partialResult, entity in
      var newPartial = partialResult
      switch entity {
      case let .post(post):
        if let avatarImgReq = post.helioData?.avatarImageRequest {
          newPartial.append(avatarImgReq)
        }
        if let extractedMedia = post.helioData?.extractedMedia {
          switch extractedMedia {
          case let .comment(comment):
            break
          case let .imgs(imgsExtracted):
            newPartial = newPartial + imgsExtracted.map(\.request)
          case let .link(link):
            if let imgReq = link.imageReq {
              newPartial.append(imgReq)
            }
          case let .video(video):
            break
          case let .yt(video):
            newPartial.append(video.thumbnailRequest)
          case .streamable:
            break
          case .repost:
            break
          case .post:
            break
          case .subreddit:
            break
          case .user:
            break
          }
        }
      default: break
      }
      return newPartial
    }
  }
}
