# ADR-0003: Feed, Comment Loading, Account Lists, and Caching

Status: Accepted

## Context

Helio renders long-lived, multi-account Reddit feeds, nested comment trees, and subscription/multireddit sidebars across iPhone, iPad, Mac Catalyst, and foldable iPhone Duo layouts. These surfaces must remain responsive while scrolling, survive runtime window resizes and layout switches without losing state, isolate multi-account mutations and fetches, and cope with Reddit API quirks, CloudKit duplicate rows, and SwiftUI/UIKit platform bugs.

This ADR captures the architectural invariants governing feed pagination, account-list persistence, comment loading and collapse state, caching, search, and adaptive multi-column layout.

## Decisions

### 1. Feed Pagination, Request Lifecycle, and Scroll Continuity

Implemented in `Sources/HelioKit/components/RedditListingFeed/FeedItemsManager.swift` and `Sources/HelioKit/components/RedditListingFeed/RedditListingFeed.swift`.

- **Immutable pagination query snapshots**: `Request` captures query parameters immutably for an entire pagination chain, including pages skipped as already read. Subsequent page fetches reuse `listRequest`'s original query parameters rather than mutated feed settings because Reddit's pagination cursor belongs to the displayed query; each new chain adopts the current page limit.
- **Synchronous fetch reservation and main-actor coalescing**: `elementAppeared` runs on the main actor and `startFetch` reserves `currentTask` synchronously before awaiting so rows appearing in the same frame coalesce into one page fetch. `fetchCaller` guards on `!Task.isCancelled` before starting because a refresh can cancel a row task before it begins executing. Initial feed loads start in an unstructured `Task` inside `onAppear` so navigation transitions do not cancel the manager's fetch.
- **Superseding, cancellation, and account isolation**:
  - `currentRequestID == requestID` guards reservation cleanup so a superseded task never clears a newer request's reservation.
  - Because Swift task cancellation is cooperative and network callbacks can still return data or errors, request ID, cancellation, and account authorization are re-checked after awaiting `fetchFn`.
  - A fetch captured while signed out must fail rather than resolving whichever account is selected later.
- **Reload continuity and paging intent**:
  - A non-clearing refresh keeps `displayMode` at `.items` while `entities` are present so displayed rows stay mounted until replaced.
  - `loadMoreHeldBack` records paging intent during an in-flight reload because still-visible rows will not re-fire `onAppear` if the refresh returns the same posts.
  - First-page and subsequent fetches deduplicate post IDs within a single page because Reddit occasionally repeats the same post in one response; the first copy is kept.
  - While the account is rate-limited, `FeedItemsManager` holds paging and reloads and schedules an automatic retry when the rate-limit window resets, rather than failing on every scroll. A pending first-page reload in `.error` (e.g. after a sort or filter change) must not be superseded by stale pagination even if the rate-limit window has just expired.
- **End-of-feed and hidden-read pagination**:
  - End-of-feed checks `after == nil || fetchedEntities.isEmpty` rather than comparing against page size: Reddit can return short pages and lossy listing decoding can skip individual children, so a nonempty page with a cursor remains pageable (while fetching without a cursor would restart from page 1).
  - `canLoadMore` includes `.onlyReadPosts` so Next Post navigation can continue past consecutive hidden-read pages, matching the feed's "keep looking" action.
- **Scroll performance and anchor preservation**:
  - `indexByID` mirrors `entities` for O(1) lookup as rows appear, avoiding quadratic scroll-time scans.
  - Appending fetched rows intentionally omits `withAnimation`, which causes scroll jumps and eagerly builds every new row in one frame.
  - Canvas mode disables media prefetching (`prefetchMedia` off) so only on-screen thumbnails load.
  - `shownRowIDs` is reference-counted rather than a `Set` because outgoing and incoming lists overlap and share the manager during layout transitions (`ScreenStates`).
  - `scrollAnchorID` is recorded when scrolling stops rather than on row disappearance (covering the list hides rows in order and would record the last row as top). `onScrollPhaseChange` requires `oldPhase != .idle` so a newly built list starting idle at the top after a layout change does not overwrite the handed-over anchor before restoring it.
  - `replaceFetch` rebinds the manager's fetch closure to the new screen when `ScreenStates` preserves a manager across a layout switch and destroys the previous screen; `RedditListingFeed` retains the closure for this handoff.
- **Post ID normalization**: When opening a post from a `link_id` (`t3_...`), the fullname prefix is stripped to the bare ID so the opened post matches feed rows.

### 2. Settings, Subreddit Metadata, Flairs, and Video Cache

Implemented in `Sources/HelioKit/globals/Defaults/CachedDefaults.swift`, `Sources/HelioKit/globals/Defaults/UserCollectionsStore.swift`, `Sources/HelioKit/models/RedditEntities/Subreddit/Subreddit.swift`, `Sources/HelioKit/models/RedditEntities/Subreddit/SubredditData.swift`, `Sources/HelioKit/components/RedditListingFeed/RedditListingFeed.swift`, and `Sources/HelioKit/models/caches/caches.swift`.

- **In-memory `Defaults` caching and hoisting**: `Defaults[key]` decodes JSON on every read, which is expensive during lazy row construction on the main thread. `RedditListingFeed` hoists settings reads to the top of `body`, and `CachedDefaults` caches decoded values in memory until any user default changes. A lock-protected generation counter is checked before storing a decoded value so concurrent `UserDefaults` writes are never overwritten by stale decodes.
- **File-backed user collections with one-time `UserDefaults` migration**: Heavy user-owned collections (`filteredSubreddits` and `likedButNotSubbed`) live in `UserCollectionsStore` as atomic JSON files under Application Support (`Helio/UserCollections`) rather than `UserDefaults` (which bloats the app's plist) or CloudKit Core Data (which would alter the synced schema). `UserCollectionsStore` keeps the decoded arrays and an O(1) filtered-subreddit `Set` in memory behind a lock and `@Observable` backing properties so SwiftUI views and swipe actions never decode JSON per row. On first launch before the `UserCollectionsStore.migratedFromUserDefaults.v1` marker is set, any legacy values in `UserDefaults` (including `Defaults`'s `[String]` array-of-JSON-elements representation for `[Subreddit]`) are migrated idempotently to disk. Legacy keys are removed and the migration marker is written only after decoding and atomic file persistence succeed; undecodable legacy payloads are preserved untouched.
- **Stable subreddit identity and settings keys**:
  - `SubredditPosts` is keyed by feed name rather than `sub.id` because a subreddit opened by name later acquires its Reddit ID when details load, which would otherwise reset its state and pages.
  - Per-subreddit settings (such as compact mode) are keyed by `Subreddit.settingsKey`: fullname (`t5_...`), which both the cached sidebar copy and Reddit's details carry, falling back to name. Mutable `id` is never used (it is fullname in the cached copy, bare ID in Reddit's details, and name when opened by name).
  - Legacy bare-ID and name keys (including `name?.lowercased()`, as subreddits opened by name were historically saved as typed) remain checked on lookup without migration because bare IDs cannot be unambiguously distinguished from names. When `subreddit?.settingsKey` changes after details load, `RedditListingFeed` lays its posts out again to apply any matching per-subreddit setting.
- **Subreddit detail merging and coalescing**:
  - `SubredditData.takingAccountState(from:)` copies only `favorited` and `subscribed` from the cached sidebar copy because other cached fields are placeholders (no description, public type).
  - `loadIfNeeded` coalesces `/api/info` lookups and recent results through `RedditInfoLoader`, whereas `refreshSubreddit` bypasses the cache to query Reddit directly.
- **Flair fetching, caching, and picker stability**:
  - `flairsFetched` deduplicates flair API requests per session (flairs rarely change) and skips virtual feeds (Home, Popular, etc.) that have no Reddit flair endpoints.
  - Flairs observed on feed posts are cached in a single background Core Data save per page to keep the main queue free during layout.
  - The flair picker stays visible whenever `selectedFilter != nil` so users can clear an active filter even if a refresh dropped that flair. Options are tagged by `pickerKey` (kind + text, excluding volatile colors that can change on background refresh and uncheck the active filter; flairs with identical text in different colors appear once).
- **Streamable cache**: `Caches.streamable` uses `ExpiringCache` backed by `NSCache` (with count limit and per-entry expiration) instead of a manual dictionary cache, so memory pressure evicts entries automatically without owning video players (`VideoPlayerHolder` owns `AVPlayer` lifetimes per ADR-0004).
- **Current column width on feed fetches**: `FeedItemsManager` carries the feed's current `contentWidth` in `FetchContext` (updated by `RedditListingFeed` as the column resizes) and relayouts fetched posts if `contentWidth` changed while the request was in flight, avoiding stale creation-time widths without watching every post's `layoutWidth`.

### 3. Account Lists, Subscriptions, Multis, and Core Data Concurrency

Implemented in `Sources/HelioKit/Persistence.swift`, `Sources/HelioKit/models/AccountLists/AccountListPersistence.swift`, `Sources/HelioKit/models/RedditEntities/Subreddit/Subreddit.swift`, and `Sources/HelioKit/views/Subreddits/SubItem.swift`.

- **Persistent store load error recovery**: `PersistenceController` loads stores synchronously (`shouldAddStoreAsynchronously = false`) and never calls `fatalError()` on store load failure. If opening the on-disk SQLite store fails with a verified corruption error (`NSFileReadCorruptFileError` or `NSSQLiteErrorDomain` codes `11`, `24`, or `26`, including wrapped underlying/detailed errors), `PersistenceController` logs via `os.Logger`, detaches any partially loaded stores, deletes the corrupted local store file and its SQLite sidecars (`-wal`, `-shm`, `-journal`), and retries once to recreate a clean local store (CloudKit and Reddit sync repopulate cached account data). For non-corruption errors (such as schema/migration errors, insufficient disk space, or permissions/path failures), `PersistenceController` preserves all existing store files untouched and falls back cleanly to an `NSInMemoryStoreType` store (`cloudKitContainerOptions = nil`), recording `storeLoadStatus` and `lastLoadError` so the app remains usable without losing local data.

- **Serialized bulk reconciliation and isolated local writers**:
  - All subscription and multireddit bulk snapshots share one private Core Data queue (`Persistence.swift`) for reads, reconciliations, and saves so parallel network fetches cannot concurrently reconcile the same missing row.
  - Local transactions queue behind bulk reconciliation (not only their save) and execute in an isolated writer context so unrelated pending edits in a shared or injected context are untouched.
  - `LocalWriteResult` is `@unchecked Sendable` safely because its save `Notification` is passed only to Core Data's cross-context merge API.
- **Grant ownership and lock discipline**:
  - Account selection is not ownership: a still-installed credential grant may finish syncing even after another account becomes selected.
  - Only the final validation/save step acquires the credential owner's lease (serializing grant invalidation). The `stateRevisions` lock covers only lightweight revision bookkeeping and never disk or network work; UI-owned `authorizationIsInstalled` checks must not wait on a lease held by a background disk save.
- **Optimistic mutation serialization, account capture, and conditional rollback**:
  - Subscription and favorite gestures share a single `MutationKey` reservation because an optimistic value is not a confirmed baseline and unsubscribing can delete a row that a pending favorite would roll back.
  - Favorite network calls invoke `doRequest` directly with `persistence.credential` rather than the selection-resolving wrapper so a mid-flight account switch cannot mutate the wrong account. Subscription mutations re-persist the server-acknowledged state even after an optimistic write.
  - `setSubscription` writes the requested explicit state rather than toggling row existence—multireddits can cache unsubscribed subreddits (which is also why `SubItem` search checks `user_is_subscriber == true`)—and preserves newer local metadata such as a newer favorite.
  - Optimistic writes capture the persisted favorite state and revision atomically inside the transaction rather than from a potentially stale view model. On failure, subscription rollback restores the confirmed favorite even if a multi recreated the deleted row with defaults, without overwriting a newer local write; favorite rollback only updates existing rows matching the expected state so it never clobbers a newer toggle or recreates an unsubscribed row.
- **Reddit API and CloudKit reconciliation invariants**:
  - Membership in Reddit's subscriptions endpoint is authoritative even when `user_is_subscriber` is omitted from an entry.
  - Pre-mutation sync responses must not recreate rows deleted by an optimistic unsubscribe, and multi members recreated after local deletion must not regain stale subscriber or favorite flags.
  - Removing a multi or member triggers orphan cleanup for non-subscribed rows previously retained by subscription sync.
  - CloudKit can deliver duplicate rows; sync deduplicates to one row per Reddit fullname without affecting other accounts' rows.

### 4. Comment Trees, Collapse State, Actions, and Theming

Implemented in `Sources/HelioKit/models/RedditEntities/Comment.swift`, `Sources/HelioKit/views/PostView/CommentTree.swift`, `Sources/HelioKit/components/Links/CommentLink/CommentLinkContent.swift`, `Sources/HelioKit/components/Links/CommentLink/CommentLinkFull.swift`, `Sources/HelioKit/models/HelioTheme/CommentsTheme.swift`, and `Sources/HelioKit/views/Settings/views/theming/Editing/ThemingCategories/CommentsThemingPanel.swift`.

- **Collapse persistence**: `CollapsedComment` Core Data records store the entity ID with its kind appended (e.g. `"abct1"`), not `data.id`. Local records only set `collapsed = true` and never overwrite Reddit's server-side collapsed flag (low score, crowd control) unless the user expands the comment; `toggleCollapsed` persists based on `newState` rather than toggling the Core Data record because Reddit can collapse a comment that has no local record.
- **Continue-thread and deep-thread stubs**: Every Reddit "continue thread" stub shares `data.id == "_"` (`"_more"` with kind appended), so `CommentTree` keys stub rows by their parent ID to avoid SwiftUI identity collisions. Tapping a truncated deep-thread stub opens the thread highlighted at the stub's `parent_id` (`t1_...`).
- **Comment actions and SwiftUI workarounds**: `SelectTextCommentAction` is filtered out of `swipeActions` because an explicit Select Text button already opens the selection sheet. Context-menu sharing uses imperative `ShareUtils.shareItem` presentation instead of `ShareLink`, which breaks inside SwiftUI `.contextMenu`.
- **Contrast and indent-guide theming**:
  - OP author names use `badge.subColor()` (the theme accent) rather than the global app tint so the High Contrast theme reaches a 7:1 contrast ratio.
  - When `indentColors` is non-empty, reply guides switch from curved `indentColor` lines to straight depth-cycled bars, `indentCurve` becomes the indent step, and `indentColor` is repurposed to draw separators between comments.

### 5. Search, Adaptive Multi-Column Layout, and Platform Chrome

Implemented in `Sources/HelioKit/views/Search.swift`, `Sources/HelioKit/models/SearchHistory.swift`, `Sources/HelioKit/views/Subreddits/Subreddits.swift`, `Sources/HelioKit/views/Subreddits/SubredditsStack.swift`, `Sources/HelioKit/components/RedditListingFeed/RedditListingFeed.swift`, and `Sources/HelioKit/views/Settings/views/theming/Editing/ThemingCategories/FeedThemingPanel.swift`.

- **Search placement, coalescing, focus, and history**:
  - `Search` uses `.searchable(..., placement: .navigationBarDrawer(displayMode: .always))` because toolbar placement hid the field on iPhone inside the tab view. `RedditListingFeed` also specifies `.navigationBarDrawer` to work around an iOS 26+ split-view toolbar bug where dismissing search immediately re-focuses it.
  - `searchType` and `searchQuery.debounced` share one `.onChange` handler so updating both together (e.g. from recent searches) triggers a single fetch.
  - Opening the Search tab focuses the field only when empty; the Search quick action always focuses it.
  - Favorite searches in `SearchHistory` are exempt from the `maxRecents` pruning cap.
- **Three-mode Posts tab and layout state handoff**:
  - `SubredditsStack` adapts between a 3-column `NavigationSplitView` on wide windows, a collapsed single stack on narrow windows (overriding `horizontalSizeClass` to `.compact` on narrow regular-width iPad/Mac windows), and a custom two-pane layout (`usesPanes`) on open iPhone Duo.
  - `SubredditsStack` tracks its measured `frame` rather than screen size. `chooseLaunchFeed` waits until `layout.measured` is true so narrow regular-width windows aren't misclassified, falling back to Home when columns show to avoid an empty feed column while preserving any feed already chosen (e.g. by a quick action).
  - `LayoutSwitch.show(...)` notifies `ScreenStates` before building the new layout's views so feeds, comments, and web history transfer across layout switches; `LayoutSwitch` is non-observable because it mutates during `body` evaluation.
  - `subsList` sets `.environment(\.navColumn, .feed)` so saved posts opened from the sidebar replace the open post in the detail column. The detail post is keyed with `.id(post)` on the full destination (two highlighted comments from one post are distinct threads) and its empty placeholder uses `selectedTheme.posts.bg` so the column does not change shade when a post opens. `FeedThemingPanel` measures its own `panelWidth` because inside an iPad form sheet it is narrower than the window.
- **Open iPhone Duo hinge layout**:
  - Open Duo always forces `showsColumns = true` because a single column would be bisected by the hinge, and filters `division` for vertical hinges (`height > width`).
  - It bypasses both `NavigationSplitView` (neither half meets `minPostWidth`, causing the feed to overlay the post) and `ArrangementView` (which splits space left of the side tab bar in half, letting the post pane cross the hinge).
  - Each pane ignores safe-area insets only on its hinge edge: the feed stack would otherwise inherit the side tab bar's inset twice, while the post pane keeps the tab bar inset so content does not run underneath it.
  - Canvas grids compute around `WindowMetrics.shared.divisionFrame` so tiles do not straddle the hinge.
- **Sidebar selection and platform chrome**:
  - `RowSelection` pairs `dest` with `inFavorites` (favorited subreddits appear twice) and delegates equality to `isSameFeed` so name-opened subreddits highlight their cached ID row. When a favorite row disappears (unstarred or hidden by search) or a feed opens externally, selection resolves to the non-Favorites row. `selectedRow` is hoisted once at the top of `body` to avoid scanning subreddits per row.
  - `sidebarSelection` blocks clearing selection beside the feed (preventing Mac Command-click from emptying the feed column) while allowing Back to clear it in a stack. `searchFocused` (`@FocusState`) is separate from `searchPresented` so Find can refocus an already-presented search field after keyboard dismissal.
  - `themedListSection` is disabled in the sidebar so system selection highlights work. iPad keeps system sidebar material; Mac Catalyst uses the theme list background with a 1pt hairline divider so the window below the toolbar is one shade.
  - `AlphabetJumper` is touch-only (omitted on Mac and whenever searching or alphabetical sections are off).
  - On Mac Catalyst: navigation titles are forced `.inline` (large titles draw a mismatched band under `MacTabToolbar`), `.sidebarToggle` is removed from the nav toolbar (owned by `MacTabToolbar`), the root post column hides its navigation bar (pushed screens keep theirs, and root web pages omit the iOS/iPadOS Close button), subs search and Edit live in a custom `safeAreaBar` (preventing floating Mac nav bar bleed-through), and `.focusEffectDisabled()` suppresses a duplicate focus ring inside the custom search capsule.

## Consequences

- Feed scrolling, paging, and layout switches avoid duplicate API calls, scroll jumps, quadratic row lookups, and lost scroll/comment state, at the cost of explicit coordination between `FeedItemsManager`, `ScreenStates`, and `LayoutSwitch`.
- Account-list persistence guarantees multi-account isolation and rollback safety against concurrent syncs and CloudKit duplicates, requiring all bulk and local mutations to route through the shared private queue and `MutationKey` reservation.
- Platform-specific layout and SwiftUI workarounds (iPhone Duo hinge panes, iOS 26+ search placement, Mac Catalyst toolbar chrome, `ShareLink` context-menu bypass) are centralized in their respective views and must be re-verified when minimum OS targets or SwiftUI behaviors change.
