//
//  FeedItemsManager.swift
//  Helio
//
//  Created by Igor Marcossi on 26/01/24.
//

import Defaults
import Nuke
import SwiftUI

@Observable
class FeedItemsManager<S> {
  typealias ItemsFetchFn = (_ lastElementId: String?, _ sorting: S?, _ searchQuery: String?, _ flair: String?) async -> (entities: [RedditEntityType]?, after: String?)?

  /// `onlyReadPosts`: paging stopped after several pages in a row held only hidden read posts.
  enum DisplayMode: String { case loading, empty, items, endOfFeed, error, onlyReadPosts }

  /// The load-more in flight, so rows appearing together start only one. Cleared only by the
  /// load-more that owns it (matched by `currentTaskID`) or by a new first page taking over.
  private var currentTask: Task<Void, Never>?
  @ObservationIgnored private var currentTaskID: UUID?
  /// A row asked for the next page while a new first page was pending. Rows still on screen won't
  /// ask again when it lands, so the load-more starts then.
  @ObservationIgnored private var loadMoreHeldBack = false
  /// Bumped on the main actor each time the first page is fetched again. A page fetched under an
  /// older generation is dropped, so a slow earlier response can't overwrite a newer one.
  @ObservationIgnored private var generation = 0
  /// The generation of the first page the shown list and its cursor came from. It lags behind
  /// `generation` while a new first page is pending, so a load-more continuing the old list is dropped.
  @ObservationIgnored private var listGeneration = 0
  /// Whether the last failure was a first page, so `retry()` fetches the first page again.
  @ObservationIgnored private var firstPageFailed = false
  /// Set once the feed starts loading its first page.
  @ObservationIgnored var initialLoadStarted = false
  var displayMode: DisplayMode = .loading
  var loadingPinned = false
  var pinnedPosts: [Post] = []
  var entities: [RedditEntityType] = [] {
    didSet { indexByID = Dictionary(entities.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first }) }
  }

  /// Rows look their position up as they appear; searching `entities` for each was quadratic.
  @ObservationIgnored private var indexByID: [String: Int] = [:]
  var loadedEntitiesIds: Set<String> = []
  var lastElementId: String?
  /// Changing the sort, search or filter doesn't touch `displayMode`: the feed shows the spinner
  /// when it starts the reload, so the spinner can't stay up for a reload that never comes.
  var sorting: S?

  var searchQuery = Debouncer("")
  var selectedFilter: ShallowCachedFilter?

  var chunkSize: Int
  private var onScreenEntities: [(entity: RedditEntityType, index: Int)] = []
  private var fetchFn: ItemsFetchFn
  private let prefetchRange = 2
  /// Whether this feed drops already-read posts when "Hide read posts" is on.
  private let hideReadPosts: Bool
  /// Pages fetched in a row whose posts were all hidden, before giving up.
  private let maxHiddenPagesInARow = 5

  init(sorting: S?, hideReadPosts: Bool = false, fetchFn: @escaping ItemsFetchFn) {
    self.sorting = sorting
    self.hideReadPosts = hideReadPosts
    self.fetchFn = fetchFn
    self.chunkSize = Defaults[.SubredditFeedDefSettings].chunkLoadSize
  }

  /// The sort, search and filter one list is fetched with.
  private struct Query {
    let sorting: S?
    let searchQuery: String?
    let filter: String?
  }

  private struct PageRequest {
    let generation: Int
    let cursor: String?
    let query: Query
  }

  /// The query the shown list was fetched with. Its later pages use it too, not the live settings,
  /// which may already have changed for a reload that hasn't started yet.
  @ObservationIgnored private var listQuery: Query?

  func fetchCaller(loadingMore: Bool) async {
    // Read with the cursor: a load-more belongs to the list its cursor continues.
    let request: PageRequest? = await MainActor.run {
      if loadingMore {
        // A refresh cancelled this load-more before it got here: the refresh starts its own.
        guard !Task.isCancelled else { return nil }
        return PageRequest(generation: self.listGeneration, cursor: self.lastElementId, query: self.listQuery ?? self.currentQuery())
      }
      self.generation += 1
      // A new first page replaces the list the pending load-more continues. That load-more's rows
      // won't appear again to ask for the next page, so ask on their behalf once the page lands.
      if self.currentTask != nil {
        self.loadMoreHeldBack = true
      }
      self.currentTask?.cancel()
      self.currentTask = nil
      self.currentTaskID = nil
      return PageRequest(generation: self.generation, cursor: nil, query: self.currentQuery())
    }
    guard let request else { return }
    await fetchPage(loadingMore: loadingMore, after: request.cursor, query: request.query, hiddenPagesInARow: 0, generation: request.generation)
  }

  private func currentQuery() -> Query {
    let custom = selectedFilter?.type == .custom
    return Query(
      sorting: sorting,
      searchQuery: custom ? selectedFilter?.text : searchQuery.debounced.isEmpty ? nil : searchQuery.debounced,
      filter: custom ? nil : selectedFilter?.text,
    )
  }

  /// Retries what failed: the first page, or the next page of the list shown.
  func retry() async {
    let fromFirstPage = await MainActor.run { firstPageFailed }
    await fetchCaller(loadingMore: !fromFirstPage)
  }

  private func fetchPage(loadingMore: Bool, after lastElementId: String?, query: Query, hiddenPagesInARow: Int, generation: Int) async {
    guard let (fetchedEntities, after) = await fetchFn(lastElementId, query.sorting, query.searchQuery, query.filter), let fetchedEntities else {
      await MainActor.run {
        guard generation == self.generation else { return }
        // A failed first page leaves the old list under its own generation: it may be for another
        // sort, search or filter, so neither paging nor a retry may continue it.
        firstPageFailed = !loadingMore
        withAnimation { displayMode = .error }
      }
      return
    }

    // Without a cursor, the next fetch would start over from the first page. A short page isn't
    // the end: Reddit can return fewer items than asked for, and undecodable items are skipped.
    let reachedEnd = after == nil || fetchedEntities.isEmpty
    let shownEntities = withoutReadPosts(fetchedEntities)
    let onlyReadPosts = shownEntities.isEmpty && !fetchedEntities.isEmpty && !reachedEnd
    // Every post on this page was already read: keep paging instead of showing a gap.
    let skipPage = onlyReadPosts && hiddenPagesInARow < maxHiddenPagesInARow
    // Stop paging, but offer to continue: no new row will appear to trigger the next page.
    let gaveUp = onlyReadPosts && !skipPage

    let applied: Bool
    if !loadingMore {
      var newLoadedEntitiesIds = Set<String>()
      for ent in shownEntities {
        newLoadedEntitiesIds.insert(ent.fullname)
      }
      // On the main actor, which renders `entities` and reads the row index.
      applied = await MainActor.run { [newLoadedEntitiesIds] in
        guard generation == self.generation else { return false }
        listGeneration = generation
        listQuery = query
        withAnimation {
          displayMode = skipPage ? .items : gaveUp ? .onlyReadPosts : shownEntities.isEmpty ? .empty : reachedEnd ? .endOfFeed : .items
          entities = shownEntities
          self.lastElementId = after
          loadedEntitiesIds = newLoadedEntitiesIds
        }
        if loadMoreHeldBack {
          loadMoreHeldBack = false
          // A skipped page already fetches on by itself.
          if displayMode == .items, !skipPage, currentTask == nil {
            startLoadingMore()
          }
        }
        return true
      }
    } else {
      var newLoadedEntitiesIds = loadedEntitiesIds
      var newEntities = entities

      for ent in shownEntities {
        if newLoadedEntitiesIds.contains(ent.fullname) {
          continue
        }
        newLoadedEntitiesIds.insert(ent.fullname)
        newEntities.append(ent)
      }

      // Awaited, so it lands before the next page's (a skipped page fetches on right away)
      // and can't overwrite that page's error.
      applied = await MainActor.run { [newEntities, newLoadedEntitiesIds] in
        // A newer first page replaced the list this page continues.
        guard generation == self.generation else { return false }
        // Don't animate appending — it causes scroll position jumps
        self.displayMode = reachedEnd ? .endOfFeed : gaveUp ? .onlyReadPosts : .items
        self.entities = newEntities
        self.lastElementId = after
        self.loadedEntitiesIds = newLoadedEntitiesIds
        return true
      }
    }

    if skipPage, applied {
      await fetchPage(loadingMore: true, after: after, query: query, hiddenPagesInARow: hiddenPagesInARow + 1, generation: generation)
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

  /// On the main actor, like the rows calling it: rows appearing together must not each start
  /// loading the next page.
  @MainActor
  func elementAppeared(entity: RedditEntityType) {
    let index = indexByID[entity.id] ?? 0
    if displayMode != .endOfFeed, !entities.isEmpty, index >= entities.count - 7, currentTask == nil {
      // While a new first page is pending, the next page of the old list would only be dropped.
      if listGeneration == generation {
        startLoadingMore()
      } else {
        loadMoreHeldBack = true
      }
    }

    let start = index - prefetchRange < 0 ? 0 : index - prefetchRange
    let end = index + (prefetchRange + 1) > entities.count ? entities.count : index + (prefetchRange + 1)
    let toPrefetch = start < end ? Array(entities[start ..< end]) : []
    let reqs = getImgReqsFrom(toPrefetch)

    Post.prefetcher.startPrefetching(with: reqs)
  }

  @MainActor
  private func startLoadingMore() {
    let id = UUID()
    currentTaskID = id
    currentTask = Task {
      await fetchCaller(loadingMore: true)
      await MainActor.run {
        if currentTaskID == id {
          currentTask = nil
          currentTaskID = nil
        }
      }
    }
  }

  @MainActor
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
