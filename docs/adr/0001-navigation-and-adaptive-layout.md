# ADR-0001: Navigation, Command Routing, and Adaptive Layout

Status: Accepted

## Context

Helio runs across iPhone, iPad, iPhone Duo (folded and unfolded postures), and Mac Catalyst. Its navigation stack, toolbar/menu commands, web link presentation, and window geometry must adapt continuously at runtime as windows resize, split views collapse or expand, and foldable devices change posture—without losing navigation state, leaking credentials, or running afoul of UIKit/SwiftUI/Mac Catalyst platform quirks.

## Decisions

### 1. Adaptive Window Metrics & Foldable (iPhone Duo) Layout

- **Window-driven layout over device idiom** (`Sources/HelioKit/globals/WindowMetrics.swift`): Layout decisions read `WindowMetrics.isWideLayout` (regular horizontal size class) rather than `userInterfaceIdiom` or `UIScreen.main.bounds`, because device idiom cannot distinguish an unfolded iPhone Duo or a narrow iPad split window. Until the first layout pass delivers the horizontal size class, startup falls back to estimating `isWide` from `width >= 700`.
- **Thread-safe observation** (`Sources/HelioKit/globals/WindowMetrics.swift`): Background work (post setup, image processing) reads metrics while the main thread updates them. Metrics are stored as `@ObservationIgnored` properties guarded by `NSLock` with manual `Observation` access/mutation notifications.
- **iPhone Duo safe-area and hinge geometry** (`Sources/HelioKit/globals/WindowMetrics.swift`):
  - `ignoresSafeArea` does not reach every inset on a folded iPhone Duo (specifically the status column), so `WindowMetricsReader` manually adds `safeAreaInsets` back.
  - `contentFrame` (in global coordinates) defines the safe-area content region so columns extending under the Duo's side tab bar can intersect with it to compute actual usable width.
  - `divisionFrame` (in global coordinates) marks the open iPhone Duo's hinge so content and controls do not span it (`nil` on displays without a hinge). It is retained across all postures—including flat—so layout does not jump when posture changes.
  - Reading `reservedRegions(kind: .division)` is guarded with `#if compiler(>=6.4)` because the API exists only in the iOS 27.1 SDK (Xcode 27.2) and is invisible to Xcode 26.
- **Dynamic tab bar measurement** (`Sources/HelioKit/extensions/ViewModifiers/measureTabBar.swift`): Tab bar height is measured in `viewDidLayoutSubviews()` rather than once on appear, because folding iPhone Duo or resizing windows repositions the tab bar. Height above the bottom safe area is reported as `0` whenever the tab bar is not a horizontal bottom bar (top-mounted on iPad and unfolded iPhone Duo; side-mounted on folded iPhone Duo).

### 2. Single-Stack / Split-View Navigation Model

- **Lossless single-stack partitioning** (`Sources/HelioKit/Navigation/Router.swift`): The posts tab's navigation state is stored as a single stack—ordered as collapsed split view displays it (the feed and screens opened from it, followed by the first post and screens opened from that)—and partitioned into feed and post columns when shown side by side. This keeps collapsing and expanding lossless.
- **Column-aware routing** (`Sources/HelioKit/Navigation/Nav.swift`, `Sources/HelioKit/Navigation/Router.swift`): Callers pass their `navColumn` environment value when opening destinations. From the posts split view's feed column, opening a post replaces the post column's screens, while any other destination stacks onto the feed column without disturbing the open post. From the post column or outside the split view, destinations push onto the top of the whole path.
- **Sidebar selection & root protection** (`Sources/HelioKit/Navigation/Router.swift`):
  - Selecting a different feed in the sidebar replaces the entire detail path so screens from the previous feed do not stay stacked on the new one.
  - While the sidebar is shown beside the detail column, the path's root feed cannot be popped by Back (which would blank the detail column). However, a post or user opened as the first screen (e.g., from a link) can always be closed. When collapsed into one stack, the feed pops normally back to the subs list.
  - On an open iPhone Duo, `feedPanePath` holds the feed and screens opened from it on top of the subs list; emptying it (returning to the subs list) also clears `postColumn` so an orphaned post is not left open.
  - A `postBesideFeed` invariant tracks when the post column is visible alongside the feed (split-view columns or open iPhone Duo's two panes), governing active-post highlighting and Next/Previous Post behavior.
- **Subreddit identity & in-place detail merging** (`Sources/HelioKit/Navigation/Router.swift`):
  - Feed matching normalizes to lowercased subreddit names rather than `==`, because name-only subreddits (from quick actions or the default feed) use their name as `id` while sidebar cached subreddits use Reddit's `id`. Built-in feeds (Home, Popular, All, Saved) are namespaced (`feed:`) so they never collide with subreddits sharing those names (such as `r/home`).
  - Re-selecting the same feed preserves its navigation stack and merges updated subreddit details in place (taking only account state via `takingAccountState` when details are already present). Updating in place keeps the feed view, loaded posts referencing the subreddit, and per-subreddit settings (such as compact mode keyed by subreddit `id`) bound to a single instance without dropping loaded pages.
- **Programmatic tab switch echo suppression** (`Sources/HelioKit/Navigation/Nav.swift`): SwiftUI's `TabView` can echo a programmatic tab change back as a same-tab tap, which would reset the target tab's stack. Echoes are ignored only until the next main-actor turn so subsequent real same-tab taps still reset the tab.
- **In-app web pages & Markdown link routing** (`Sources/HelioKit/Navigation/Nav.swift`, `Sources/HelioKit/Navigation/Router.swift`, `Sources/HelioKit/Navigation/injectInTabDestinations.swift`):
  - In the posts tab, Reddit links (posts, subreddits, users) and in-app web pages open from the originating column; other links or tabs fall back to app-level URL handling. Markdown links are intercepted via `ColumnLinkOpener` because app-level URL handling lacks `navColumn` context.
  - Web links open in `WebPageScreen` (`.web(URL)`) instead of Safari's view controller (`openURL`) on Mac Catalyst (where `openURL` launches the external default browser and Safari's view cannot embed in a window), beside the feed in split view (where Safari's sheet would cover both columns), and everywhere when a web extension is enabled (since Safari's view runs none of the app's extensions). Phones in single-stack mode without extensions keep Safari's sheet.
  - `WebPageScreen` intentionally bypasses `readableWidth()` so web pages lay out across the full column width.
- **Full-width back-swipe gesture** (`Sources/HelioKit/Navigation/Router.swift`): `"Navigation everywhere"` (`swipeAnywhereEnabled`) uses iOS 26's `interactiveContentPopGestureRecognizer` while leaving the standard edge `interactivePopGestureRecognizer` untouched. It defaults to `false` because full-width back swipe competes with horizontal post/comment swipe actions, which are disabled while it is on.

### 3. Command Target Routing, Menu Bar, Toolbar & Keyboard Shortcuts

- **Active target registration & lifetime** (`Sources/HelioKit/Navigation/CommandTargets.swift`):
  - Screens register while shown via `commandTarget(_:)`. In a single stack, commands follow the top screen; in the posts split view, they track both the feed column and the post column, with Refresh and Find targeting the screen shown last.
  - Screens pushed over a posts-tab column root do not know their column; fallback resolution maps `.post` to `.post` and everything else to `.feed`.
  - `CommandTargetLifetime` ties cleanup to a reference type's `deinit` stored in `@State`, so covered screens retain registration while discarded screens release it.
- **Collapsed-stack feed retention & cleanup** (`Sources/HelioKit/Navigation/CommandTargets.swift`):
  - `postsFeed` is retained after unregistering because in a collapsed stack an opened post covers its feed while Next/Previous Post still needs the feed's post list.
  - `forgetPostsFeed` clears `postsFeed` when a stack is discarded (e.g., on account switch) so old posts and captured credentials are not retained.
- **Adjacent post navigation & covered-feed pagination** (`Sources/HelioKit/Navigation/CommandTargets.swift`):
  - Beside the feed, Next/Previous Post moves from the post column's root post even under pushed screens (matching list selection behavior); in a single stack, it only works from the post itself, not from a profile or another post pushed over it.
  - `feedPostID` requires the feed column's top screen to be a post-listing feed so standalone posts (opened from the subs list or a link) do not navigate against a stale feed, and profiles pushed over a standalone post do not hijack it.
  - `CommandTargets.Target` exposes `canLoadMore`/`loadMore` because a feed covered by its post cannot trigger row-appear pagination. Next Post loops up to `maxPagesPerStep` pages because mixed listings like Saved can return pages containing only comments and zero posts.
- **Modal & UIKit presentation blocking** (`Sources/HelioKit/Navigation/CommandTargets.swift`, `Sources/HelioKit/Navigation/NavCommands.swift`):
  - `.modal` targets (such as a reply composer or full-screen media viewer) block commands from acting behind them or closing them by navigating.
  - `isCoveredObservably` intentionally excludes UIKit presentations (such as share sheets) when computing SwiftUI menu enabled state because UIKit dismissals do not trigger SwiftUI menu redraws and would leave items stuck disabled; commands check full `isCovered` (including `windowPresentsSomething()`) at execution time.
  - `windowPresentsSomething()` walks the entire `presentedViewController` chain (because a share sheet can sit on top of an active `UISearchController`) while excluding `UISearchController` itself so Find and Refresh keep working during active search.
- **Cross-platform `ScreenAction` & Mac toolbar stability** (`Sources/HelioKit/Navigation/ScreenAction.swift`):
  - Screens register actions with `CommandTargets`; `NavCommands` exposes them in the menu bar, Mac renders them in `MacTabToolbar` (`NSToolbar`) above the screen's column, and iPhone/iPad keep their SwiftUI navigation bar menus.
  - `ScreenAction.Entry` implements `Equatable` by visual presentation only, ignoring closure identity.
  - `toolbarEdit` computes a minimal middle-range diff preserving shared prefix/suffix items so tabs and the sidebar button are not rebuilt as screen actions come and go.
- **Flair filter & Account menu invariants** (`Sources/HelioKit/Navigation/ScreenAction.swift`, `Sources/HelioKit/Navigation/NavCommands.swift`):
  - Flairs are deduplicated by `pickerKey` (the cache can hold identical flair text in different colors), active selection matches by `pickerKey` (colors can change across refreshes), and the Flair section remains shown when `selected != nil` even if the list is empty so users can clear an active filter dropped by a refresh.
  - The Accounts menu is accessible from any tab (blocked while covered because Log Out's alert cannot present over a sheet). `NavCommands` observes `generalDefSettings` and passes the observed `selectedID` so the checkmark tracks switches made elsewhere. Resolution falls back to `manager.selectedCredential` if the stored ID was deleted, and switching checks for any valid credential different from `selected` (rather than `count > 1`) so users can switch away from a signed-out selected account when one other account exists.
- **Menu bar & keyboard shortcut platform quirks** (`Sources/HelioKit/Navigation/NavCommands.swift`, `Sources/HelioKit/Navigation/ScreenAction.swift`):
  - Every keyboard shortcut requires Command (and Option for arrows) so none hijack text-field input.
  - Screen-action menus always render as submenus (using disabled placeholder items when unavailable): switching between a submenu and a regular item reorders items on Mac, and submenus cannot be disabled directly on Mac.
  - Menu bar `Toggle` items are text-only: on Mac Catalyst, a menu bar `Toggle` with an icon never invokes its action.
  - Feed and post menus live in the single `CommandGroup(before: .toolbar)` because actions in a second group before toolbar items never fire on Mac.
  - Edit > Find is placed after `.pasteboard` instead of replacing `.textEditing`, because `.textEditing` never renders on iPad (which would also suppress its shortcut).
  - Reddit API state guards disable vote commands on archived posts and reply commands on archived or locked posts.

### 4. Home Screen Quick Actions

- **Slot budget & backwards compatibility** (`Sources/HelioKit/Navigation/QuickAction.swift`): iOS displays at most 4 Home Screen quick actions; Search and Saved take 2, fixing `maxSubreddits` at 2. Capitalized shortcut type strings from older app versions remain supported, and legacy `"subFav"` items (which stored placeholder `"sub"`) read `localizedTitle` until shortcuts are rebuilt.
- **Target resolution & focus** (`Sources/HelioKit/Navigation/QuickAction.swift`, `Sources/HelioKit/Navigation/Nav.swift`):
  - `cachedSubreddit` fetches the current account's `CachedSub` so the sidebar highlights it as selected, while still treating a favorite named like a built-in feed (`r/home`) as that subreddit.
  - `popToFeed` closes screens pushed on an already-selected feed so quick actions always land on the feed itself.
  - `searchFocusRequest` is a monotonic counter rather than a boolean so repeated Search quick actions re-focus the field even when the Search tab is already active.

## Consequences

- **Consistent multi-form-factor behavior**: Window resizing, iPad multitasking, Mac Catalyst toolbars/menus, and iPhone Duo folding share one navigation model and metrics source without losing stack state or spanning hardware hinges.
- **Explicit platform workarounds**: Several invariants exist specifically to counter SwiftUI, UIKit, and Mac Catalyst bugs (menu reordering, icon-bearing toggles, `.textEditing` on iPad, `TabView` selection echoes, `ignoresSafeArea` on Duo). Removing or simplifying them requires re-verifying across iPhone, iPad, iPhone Duo, and Mac Catalyst.
- **Tight lifecycle coupling**: Covered-feed retention (`postsFeed`) and `CommandTargetLifetime` rely on explicit teardown (`forgetPostsFeed`) during stack resets and account switches to avoid retaining stale posts or credentials.
