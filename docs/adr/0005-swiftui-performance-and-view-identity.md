# ADR-0005: SwiftUI Performance, View Identity, and Layout Invariants

Status: Accepted

## Context

Helio renders long, media-rich Reddit feeds and deeply nested comment trees across iPhone, iPad multitasking, folded and unfolded iPhone Duo, and resizable Mac Catalyst windows. In SwiftUI, naive `@Observable` usage, repeated Markdown parsing, unthrottled relayouts during live window resizing, or shared web/media state between side-by-side columns quickly cause frame drops, redundant network fetches, and broken playback or selection behavior.

This ADR captures the performance, view-identity, text-scaling, and layout invariants that keep scrolling and resizing responsive while preserving media state and cross-platform layout fidelity.

## Decisions

### Entity Identity and Observation

- **Keep entity identity `@ObservationIgnored` and pre-join `joinedID`**: In `Sources/HelioKit/models/RedditEntities/GenericRedditEntity.swift`, `_id` is marked `@ObservationIgnored` and `joinedID` (`_id + kind`) is updated in `didSet` rather than concatenated on every read.
  - *Why*: Views do not observe identity changes, and reading an observed property on a generic `@Observable` class constructs a key path at runtime on every access—a cost that rows, `ForEach`, and `==` would otherwise pay on every `id` lookup. Caching `joinedID` also eliminates repeated string allocations on the hot `Identifiable` path.

### Post Relayout, Media Reuse, and Multi-Column Isolation

Implemented in `Sources/HelioKit/models/RedditEntities/Post/Post+Relayout.swift`:

- **Re-extract only width-dependent or compact-dependent media**:
  - On width changes, only `.imgs` is width-dependent (image requests are sized for the column). Link previews, videos, and embeds are not re-extracted, avoiding redundant link-preview metadata fetches and preserving playback state. YouTube thumbnails are refreshed via `relayoutingParts`.
  - On compact/large row toggles (`dependsOnCompact`), only images (thumbnail requests) and link previews differ; async-resolved media such as Streamable videos are preserved rather than discarded.
- **Relayout embedded reposts in place**: Embedded reposts are laid out in place instead of re-extracted, because re-extracting would instantiate a new embedded post and lose its vote state and resolved previews.
- **Isolate post page layout from feed row layout**: `pageLayout` is cached independently for a post page's `contentWidth` and window height (recomputed when width, window height, or the row's media change) without mutating the feed row's own layout. This prevents mutual relayout loops when a post is open beside its feed in a multi-column layout.
- **Share non-YouTube media with the feed row, but isolate YouTube players per page**: Post pages re-extract width-dependent images at the detail column's size while sharing link previews and videos with the feed row so previews stay intact and videos keep playing seamlessly. Each post page gets its own `YouTubePlayer` (`PageYouTubePlayer`), created once per video for as long as the page is shown—never shared with the feed row or another page—because showing two views of the same post simultaneously (such as a post beside its feed, or a post at the feed column's root beside its thread) would share a single `WKWebView` and playing in one would pull the video out of the other.
- **Debounce relayouts during live window resizing**: Post relayout waits for column width or window height changes (media height is capped by window height) to settle before running, because resizing a Mac window emits size updates every frame. Full relayouts also run when compact mode, content text size, or theme title styling changes, since those affect every row.

### Content Text Scaling and Dynamic Type

Implemented in `Sources/HelioKit/globals/ContentTextScale.swift` and `Sources/HelioKit/globals/Defaults/defaults.swift`:

- **Mirror Dynamic Type in a thread-safe global (`ContentTextScale`)**: Content text (post titles, bodies, comments, meta lines, and link previews) scales with the system text size like `UIFontMetrics`, keeping theme sizes unchanged at the default text size and leaving controls and icons at fixed sizes. Because feed titles are measured off the main thread, the active text scale is stored in `ContentTextScale`—synced from the SwiftUI environment via `trackContentTextScale()`—rather than read from a main-thread trait collection.
- **Apply `trackContentTextScale()` at the app root before feeds load**: The root view must install `trackContentTextScale()` before feeds fetch and measure their first posts so initial row measurements use the window's actual text size and user adjustment.
- **Read `contentTypeSize` instead of `dynamicTypeSize` in content views**: Content views must read the custom `contentTypeSize` environment value (which applies Settings > Appearance > Text Size via `ContentTextScale.adjusted(_:by:)`) rather than SwiftUI's `dynamicTypeSize`.
- **Cap `.meta` text at `.accessibility2`**: Titles and bodies wrap and follow Dynamic Type all the way up, but `.meta` lines stop at `.accessibility2` because beyond AX2 a post's stats overflow beside its `•••` and vote buttons on iPhone.
- **Handle Mac Catalyst's lack of Dynamic Type**: Mac Catalyst has no system Dynamic Type and `UIFontMetrics` does not scale there. Accordingly, `adjusted(_:by:)` starts from `.large` (the baseline the Mac layout was designed for), Settings > Appearance > Text Size serves as the sole text-size control on Mac, and scaling uses a custom `macScale` multiplier following iOS's body style sizes.
- **Store `contentTextSizeAdjustment` under its own `Defaults` key**: `contentTextSizeAdjustment` is persisted as a standalone `Defaults` key rather than a field on an existing settings struct, because adding a new field to an existing `Codable` settings struct would break decoding of previously stored user settings.

### Markdown Caching, Text Selection, and View Sizing

- **Cache formatted and parsed `MarkdownContent`**: In `Sources/HelioKit/components/Markdown Handling/External to Internal Links.swift`, text rewritten by `formatForMarkdown` and parsed into `MarkdownContent` is cached by text and spoiler state. Feed and comment rows re-evaluate on every state update and every scroll back into view, so caching ensures each body is formatted and parsed once.
- **Branch on concrete `TextSelectability` types**: In `Sources/HelioKit/components/Markdown Handling/Helio MD.swift`, selectable vs. non-selectable Markdown bodies branch on SwiftUI's concrete `.enabled` and `.disabled` types instead of a dynamic conformance. SwiftUI reads `TextSelectability.allowsSelection` at the type level (`static var allowsSelection`), so a single custom conformance cannot toggle selection on and off.
- **Size `LiveTextInteraction` to the window, not the image or screen**: In `Sources/HelioKit/components/LiveTextInteraction.swift`, `intrinsicContentSize` returns the window's bounds rather than the image's size or `UIScreen.main.bounds`. This lets SwiftUI size the view by its frame while remaining accurate when the window is smaller than the screen (iPad multitasking, Mac windows, and folded iPhone Duo).

## Consequences

- Scrolling, `ForEach` diffing, and live Mac window resizing avoid avoidable runtime key-path construction, repeated string/Markdown work, and per-frame relayout thrashing.
- Multi-column layouts can display a feed and an open post simultaneously without relayout ping-pong, lost repost state, re-fetched link previews, or YouTube playback hijacking.
- New content views must remember to read `contentTypeSize` (not `dynamicTypeSize`), new settings must preserve `Defaults` `Codable` compatibility, and any future media types added to `Post` must explicitly declare whether they depend on column width or compact mode in `Post+Relayout.swift`.
