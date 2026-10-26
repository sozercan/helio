//
//  FeedItemsManager.swift
//  winston
//
//  Created by Igor Marcossi on 26/01/24.
//

import SwiftUI
import Defaults
import Nuke

@Observable
class FeedItemsManager<S> {
    typealias ItemsFetchFn = (_ lastElementId: String?, _ sorting: S?, _ searchQuery: String?, _ flair: String?) async -> (entities: [RedditEntityType]?, after: String?)?
    
    /// `onlyReadPosts`: paging stopped after several pages in a row held only hidden read posts.
    enum DisplayMode: String { case loading, empty, items, endOfFeed, error, onlyReadPosts }
    
    private var currentTask: Task<(), Never>? = nil
    var displayMode: DisplayMode = .loading
    var loadingPinned = false
    var pinnedPosts: [Post] = []
    var entities: [RedditEntityType] = []
    var loadedEntitiesIds: Set<String> = []
    var lastElementId: String? = nil
    var sorting: S? {
        willSet { withAnimation { displayMode = .loading } }
    }
    var searchQuery = Debouncer("")
    var selectedFilter: ShallowCachedFilter? {
        willSet { withAnimation { displayMode = .loading } }
    }
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
    
    func fetchCaller(loadingMore: Bool) async {
        await fetchPage(loadingMore: loadingMore, after: loadingMore ? lastElementId : nil, hiddenPagesInARow: 0)
        self.currentTask = nil
    }
    
    private func fetchPage(loadingMore: Bool, after lastElementId: String?, hiddenPagesInARow: Int) async {
        if !loadingMore, let currentTask, !currentTask.isCancelled {
            currentTask.cancel()
        }

        let searchQuery = selectedFilter?.type == .custom ? selectedFilter?.text : searchQuery.debounced.isEmpty ? nil : searchQuery.debounced
        let filter = selectedFilter?.type != .custom ? selectedFilter?.text : nil

        guard let (fetchedEntities, after) = await fetchFn(lastElementId, sorting, searchQuery, filter), let fetchedEntities else {
            await MainActor.run { withAnimation { displayMode = .error } }
            return
        }
        
        // Without a cursor, the next fetch would start over from the first page.
        let reachedEnd = fetchedEntities.count < chunkSize || after == nil
        let shownEntities = withoutReadPosts(fetchedEntities)
        let onlyReadPosts = shownEntities.isEmpty && !fetchedEntities.isEmpty && !reachedEnd
        // Every post on this page was already read: keep paging instead of showing a gap.
        let skipPage = onlyReadPosts && hiddenPagesInARow < maxHiddenPagesInARow
        // Stop paging, but offer to continue: no new row will appear to trigger the next page.
        let gaveUp = onlyReadPosts && !skipPage
            
        if !loadingMore {
            var newLoadedEntitiesIds = Set<String>()
            shownEntities.forEach { ent in
                newLoadedEntitiesIds.insert(ent.fullname)
            }
            withAnimation {
                displayMode = skipPage ? .items : gaveUp ? .onlyReadPosts : shownEntities.isEmpty ? .empty : reachedEnd ? .endOfFeed : .items
                entities = shownEntities
                self.lastElementId = after
                loadedEntitiesIds = newLoadedEntitiesIds
            }
        } else {
            var newLoadedEntitiesIds = loadedEntitiesIds
            var newEntities = entities
            
            shownEntities.forEach { ent in
                if newLoadedEntitiesIds.contains(ent.fullname) { return }
                newLoadedEntitiesIds.insert(ent.fullname)
                newEntities.append(ent)
            }
            
            // Awaited, so it lands before the next page's (a skipped page fetches on right away)
            // and can't overwrite that page's error.
            await MainActor.run { [newEntities, newLoadedEntitiesIds] in
                // Don't animate appending — it causes scroll position jumps
                self.displayMode = reachedEnd ? .endOfFeed : gaveUp ? .onlyReadPosts : .items
                self.entities = newEntities
                self.lastElementId = after
                self.loadedEntitiesIds = newLoadedEntitiesIds
            }
        }
        
        if skipPage {
            await fetchPage(loadingMore: true, after: after, hiddenPagesInARow: hiddenPagesInARow + 1)
        }
    }
    
    private func withoutReadPosts(_ entities: [RedditEntityType]) -> [RedditEntityType] {
        guard hideReadPosts, Defaults[.PostLinkDefSettings].hideOnRead else { return entities }
        return entities.filter { entity in
            if case .post(let post) = entity { return !(post.data?.winstonSeen ?? false) }
            return true
        }
    }
    
    func elementAppeared(entity: RedditEntityType, index: Int) async {
        if displayMode != .endOfFeed, entities.count > 0, index >= entities.count - 7, currentTask == nil {
            self.currentTask = Task { await fetchCaller(loadingMore: true) }
        }
        
        let start = index - prefetchRange < 0 ? 0 : index - prefetchRange
        let end = index + (prefetchRange + 1) > entities.count ? entities.count : index + (prefetchRange + 1)
        let toPrefetch = start < end ? Array(entities[start..<end]) : []
        let reqs = getImgReqsFrom(toPrefetch)
        
        Post.prefetcher.startPrefetching(with: reqs)
    }
    
    func elementDisappeared(entity: RedditEntityType, index: Int) async {
        let reqs = getImgReqsFrom([entity])
        Post.prefetcher.stopPrefetching(with: reqs)
    }
    
    private func getImgReqsFrom(_ entities: [RedditEntityType]) -> [ImageRequest] {
        entities.reduce([] as [ImageRequest]) { partialResult, entity in
            var newPartial = partialResult
            switch entity {
            case .post(let post):
                if let avatarImgReq = post.winstonData?.avatarImageRequest {
                    newPartial.append(avatarImgReq)
                }
                if let extractedMedia = post.winstonData?.extractedMedia {
                    switch extractedMedia {
                    case .comment(let comment):
                        break
                    case .imgs(let imgsExtracted):
                        newPartial = newPartial + imgsExtracted.map { $0.request }
                    case .link(let link):
                        if let imgReq = link.imageReq {
                            newPartial.append(imgReq)
                        }
                        break
                    case .video(let video):
                        break
                    case .yt(let video):
                        newPartial.append(video.thumbnailRequest)
                    case .streamable(_):
                        break
                    case .repost(_):
                        break
                    case .post(_):
                        break
                    case .subreddit(_):
                        break
                    case .user(_):
                        break
                    }
                }
                break
            default: break
            }
            return newPartial
        }
    }
}
