# ADR-0004: Media Rendering, Video Pipeline Lifecycle, and Lightbox

Status: Accepted

## Context

Helio displays images, animated GIFs, inline autoplaying videos, link previews, and a fullscreen swipe-through lightbox across feeds, post detail pages, and Picture in Picture (PiP). On iOS and Mac Catalyst, media surfaces face strict hardware limits (~16 simultaneous video decode pipelines), memory pressure from large images and multi-hundred-post feed timelines, subtle SwiftUI/UIKit gesture and lifecycle quirks, and foldable iPhone Duo safe-area constraints.

This ADR captures the architectural invariants governing media extraction, image downsampling, link preview caching, inline video lifecycle, fullscreen lightbox interaction, and Picture in Picture.

## Decisions

### 1. Media Extraction, Image Downsampling, and Layout Stability

Implemented in `Sources/HelioKit/components/Media/mediaExtractor.swift`, `Sources/HelioKit/components/Media/ImageMediaPost/ImageMediaPost.swift`, `Sources/HelioKit/components/Media/MediaPresenter.swift`, and `Sources/HelioKit/components/NukeOpt/FetchImageOpt.swift`.

- **Extraction precedence and crossposts**:
  - `mediaExtractor` branch order is load-bearing. Crosspost extraction must run before generic URL/media checks because a crosspost's own fields often carry a bare `v.redd.it` URL without playable `media` metadata; the original post provides the playable media.
  - Embedded crossposts pass `fetchAvatar: false` because the outer post or page owns avatar registration for the entire embedded tree.
- **Deferred network fetches**: When `fetchLinkMetadata` is `false`, link previews do not download their target pages and linked Reddit posts, comments, users, and subreddits are deferred (`PostHelioData.deferredMedia`) until actually shown, preventing off-screen rows from issuing network requests.
- **YouTube oEmbed tolerance**: Reddit's YouTube oEmbed payloads frequently omit thumbnail, author, and dimension fields, so extraction requires only the video ID.
- **Privacy-preserving URL normalization**: Media URLs strip tracking parameters while preserving all remaining query parameters, because signed Reddit previews and token-gated CDNs fail to load without their query tokens.
- **ImageIO downsampling and GIF exclusion**:
  - Static images and thumbnails use ImageIO downsampling so large images are decoded directly at display size rather than decoded full-size and redrawn smaller.
  - GIFs are excluded from ImageIO thumbnail downsampling because it strips animation frames (`compactThumbnailsGIFs` preserves compact GIF thumbnail decoding).
  - Single images resize by `contentWidth` (narrower when height-capped) rather than square `aspectFill` (used by gallery cells), avoiding multi-fold pixel/memory blowup on wide images. Compact thumbnails and images without Reddit-supplied dimensions use a square frame.
- **Layout stability and no-crop tall images**:
  - When Reddit omits image or video dimensions, media defaults to a square frame matching `getPostDimensions` so feed rows do not jump in height once media loads (`ImageMediaPost.swift`, `VideoPlayerPost.swift`).
  - Images taller than the height cap (common in landscape where the window is short) are letterboxed narrower and centered on a band rather than cropping their top and bottom.
- **Post-page media size isolation**: `MediaPresenter` receives `pageMediaSize` from the post page's own layout rather than reading the shared post cache, preventing two open pages of the same post in different columns from overwriting each other's layout dimensions.
- **Observable invalidation hygiene**: `FetchImageOpt.reset()` guards state mutations so unchanged values are not republished, avoiding redundant `@Observable` view invalidations.

### 2. Link Previews and Open Graph Caching

Implemented in `Sources/HelioKit/components/Media/PreviewLink/PreviewModel.swift` and `Sources/HelioKit/components/Media/PreviewLink/PreviewLinkContent.swift`.

- **Shared model cache and download deduplication**:
  - `PreviewModel` shares a single model per link across compact and full layouts, window resizes, and view rebuilds. `LinkMetadataLoader` guarantees at most one Open Graph download per page regardless of how many previews reference it.
  - Failed downloads are evicted from the cache so subsequent layouts can retry (with `LinkMetadataLoader` spacing out retries). When `fetch` is `false` (e.g. canvas layouts that do not show previews), downloading is deferred until `loadIfNeeded()` runs when the preview becomes visible.
- **Reference identity equality and refresh reloads**:
  - `PreviewModel` equality uses reference identity (`===`) rather than URL equality so a cached `Post.pageLayout` picks up a newly created model after a refresh when the prior model may have failed.
  - `PreviewLinkContent` keys its `.task` by `ObjectIdentifier(viewModel)` so a model swapped in by a refresh loads even when the view is already visible.
- **Off-main thread safety and scroll smoothness**:
  - `started` is guarded by a `Mutex` because post layouts are computed concurrently off the main thread.
  - Metadata updates intentionally omit animation because animated commits landing during feed scrolling cause scroll hitches.
- **Contrast and corner concentricity**: `PreviewLinkContent` uses the theme's `badge.statsText` color instead of `Color.secondaryText` to maintain 7:1 WCAG AAA contrast in High Contrast, and applies a 10pt thumbnail corner radius inside cards (16pt card radius minus 6pt padding) for concentricity versus 12pt in standalone compact rows.

### 3. Inline Video Lifecycle and Hardware Decode Pipeline Budget

Implemented in `Sources/HelioKit/components/Media/VideoPlayerPost.swift`.

- **View-scoped `AVPlayer` ownership**: `VideoPlayerHolder` owns a single `AVPlayer` via `@StateObject` so `deinit` runs reliably when SwiftUI de-realizes a `List` cell (unlike `onDisappear`, which `List` fires unreliably). This bounds live player count to the `List` realization window, replacing an earlier design where append-only `PostHelioData` pinned `SharedVideo`-owned players alive until iOS froze video playback.
- **Hardware decode-pipeline budget (~16 simultaneous pipelines)**:
  - Because SwiftUI's `VideoPlayer` provides no teardown hook, inline feed/detail video uses a bare `AVPlayerLayer` (`PlayerLayerHostView` / `InlinePlayerLayer`) mounted only when the cell is visible and not in fullscreen. Off-screen cells render `Color.clear`, invoking `dismantleUIView` to release the `AVPlayerLayer` decode pipeline while leaving the shared cached `AVPlayer` intact for instant resume.
  - For `AVPlayerViewController`-backed views, `dismantleUIView` explicitly calls `removeFromParent()` so scrolled-past cells do not leak child view controllers and decode sessions on the long-lived feed controller.
- **Synchronous disappear pause**: Pausing and seeking to zero on disappear runs synchronously so a deferred pause cannot execute after the cell reappears and freeze playback at 0:00.
- **Looping, stall recovery, and failure detection**:
  - `actionAtItemEnd = .none` keeps the player rolling at item end so seeking to `.zero` loops without pausing.
  - `AVPlayerItemPlaybackStalled` waits a 4-second grace period before reloading because transient buffer refills normally recover on their own (shared with `LightBoxVideo.swift`).
  - Because AVFoundation posts no notification when an item fails to become playable, KVO-backed `itemFailed` state triggers retries.
- **Observer cleanup and view updates**:
  - `NotificationCenter` block observers are stored in a token bag and removed by token in `deinit` (`removeObserver(self, ...)` is a no-op for block observers), preventing leaks even when SwiftUI recycles cells without `onDisappear`.
  - `VideoPlayerPost.==` includes `contentWidth` and layout inputs so rotation and column resizes update video dimensions.
  - `UIAccessibility.isVideoAutoplayEnabled` is mirrored into `@State` so toggling the system Auto-Play Video Previews setting redraws the player.

### 4. Fullscreen Lightbox, Gestures, and Scrubbing

Implemented in `Sources/HelioKit/components/LightBoxImage/LightBoxImage.swift`, `Sources/HelioKit/components/LightBoxImage/LightBoxTimeline.swift`, `Sources/HelioKit/components/LightBoxImage/LightBoxGestures.swift`, `Sources/HelioKit/components/LightBoxImage/ZoomableImageView.swift`, `Sources/HelioKit/components/LightBoxImage/LightBoxOverlay.swift`, `Sources/HelioKit/components/LightBoxImage/LightBoxElementView.swift`, and `Sources/HelioKit/components/Media/MediaScrubbing.swift`.

- **Window-level presentation and sheet boundary**: `LightBoxPresenter` is hosted above the window's tab view so rotating or resizing (which rebuilds feed rows) does not dismiss an open lightbox. Inside sheets, `lightBoxPresenter` is `nil` because a presenter hosted above the tabs cannot cover a presented sheet.
- **Feed timeline, privacy, and read-state deduplication**:
  - `LightBoxTimeline.around` builds a swipe-through timeline from neighboring feed posts and falls back to the opened post's own media when outside a feed or viewing a crosspost's original.
  - Blurred NSFW posts are excluded from swipe-through timelines and appear only when opened directly.
  - `LightBoxPost` carries a `key` to distinguish posts so paging within a multi-image gallery does not re-mark the same post read.
  - `FeedRevealRequest` carries a unique `UUID` token so repeated scroll-to-post requests for the same `postID` still trigger change observers.
- **Windowed resource loading and index-keyed pages**:
  - `ForEach` keys lightbox pages by index rather than media identity because a feed can contain duplicate images.
  - Only pages adjacent to `activeIndex` load media, and `LightBoxMediaStore` creates and evicts GIF scrubbers and video players within that window so a feed lightbox spanning hundreds of pages holds only a few active resources.
- **Borrowed video players and audio-session handoff**:
  - `.video` optionally borrows the originating feed row's `VideoPlayerHolder` to continue playback seamlessly without reloading; neighboring posts leave it `nil`.
  - For borrowed players, the lightbox only retries items that remain failed and leaves early stops and stalls to the feed row to avoid conflicting reloads (`LightBoxVideo.swift`).
  - When paging between adjacent videos, the new video activates before the old one deactivates so the audio session is not dropped between them.
- **Safe areas, iPhone Duo geometry, and zoom stability**:
  - `GeometryReader` wraps the outer lightbox rather than the pages `HStack` (whose width is the sum of all pages). `pageWidth` measures the lightbox container rather than the window because on a folded iPhone Duo it stops short of the status column, which `.ignoresSafeArea()` does not reach.
  - Because `.ignoresSafeArea()` zeroes SwiftUI safe areas inside the lightbox, `sideInsets` reads `WindowMetrics.contentFrame` manually to keep the title, author, and action buttons clear of the folded Duo's camera and status column. The Close button overlay sits outside `.ignoresSafeArea()`, and `LightBoxOverlay` reserves 56pt trailing padding for it.
  - Plain-style overlay buttons apply their 44×44 hit target frame to the `Label` so the entire circle receives taps.
  - `ZoomableImageView` sets `contentInsetAdjustmentBehavior = .never` (preventing a black safe-area band on touch, notably on the folded Duo's status column) and keeps `hostedView.frame` and `scrollView.contentSize` synced while unzoomed so the next pinch scales from the right baseline instead of a stale or zero size.
- **Gesture arbitration and scrubbing**:
  - UIKit gestures (`LightBoxGestures.swift`) handle hold-then-drag scrubbing (continuing to track the finger after cancelling the SwiftUI lightbox drag) and two-finger trackpad paging (accepting scroll events only so touch drags still reach the lightbox).
  - Plain horizontal swipes navigate media while hold-then-drag scrubs videos/GIFs; horizontal swipe threshold is capped at 200pt (half a phone width) so paging stays ergonomic on wide iPad and Mac windows.
  - `@GestureState` tracks active drags (`LightBoxImage.swift`, `MediaScrubbing.swift`) because cancelled SwiftUI drags skip `onEnded`, allowing `.onChange(of: dragging)` to reset `dragOffset` and `dragAxis`. In `ZoomableImageView`, `tapGesture` requires the hold gesture to fail so resting a finger to scrub does not toggle controls.
  - `MediaScrubbing` caps a full-width swipe at 60 seconds (`maxSecondsPerWidth`) while shorter clips span full width; elapsed time rounds down and remaining time rounds up so they always sum to duration. `VideoScrubber` uses adaptive seek tolerance (matching finger travel since the last seek) with latest-only coalescing during drags to avoid ~200ms exact-seek stalls, settling with an exact seek when the finger rests or lifts.
- **Accessibility and Mac command isolation**:
  - `LightBoxElementView` keeps Live Text recognized text and codes reachable to VoiceOver instead of collapsing them into the image's accessibility label.
  - `LightBoxImage` registers a `.modal` command target so Mac menu-bar Post commands cannot navigate the underlying post while the lightbox covers it.

### 5. Picture in Picture (PiP) Lifetime and Audio Handoff

Implemented in `Sources/HelioKit/components/LightBoxImage/LightBoxVideo.swift` and `Sources/HelioKit/components/Media/VideoPlayerPost.swift`.

- **Outliving the lightbox and feed row**: `LightBoxVideo` owns `layerView` (instead of the SwiftUI page view) and `PictureInPicture` retains strong references to the player holder and owner so PiP continues floating after the lightbox closes and even if the originating feed row is destroyed.
- **Delegate and observer lifetimes**: `LightBoxVideo` retains the `AVPictureInPictureController` delegate because AVKit holds it weakly. Loop observers remain registered until release (not deactivation) so videos keep looping in PiP, and observer teardown is deferred via `released` until PiP ends.
- **UI restoration and audio resume**: PiP restoration calls `completionHandler(false)` because the lightbox intentionally closed when PiP started. Because entering PiP from fullscreen skipped resuming other apps' audio, PiP teardown calls `scheduleAudioMixing(true)` when no fullscreen players remain.

## Consequences

- Bounding `AVPlayer` and `AVPlayerLayer` lifetimes to visible cells and a small lightbox window prevents hardware decode-pipeline exhaustion and unbounded memory growth across long browsing sessions.
- ImageIO downsampling, deferred media extraction, shared `PreviewModel` caching, and unanimated metadata commits keep scrolling smooth and network usage minimal, at the cost of strict ordering in `mediaExtractor` and explicit GIF/dimension edge-case handling.
- UIKit gesture bridges, manual iPhone Duo safe-area calculations, and model-owned PiP layers add targeted UIKit/AVKit complexity where SwiftUI's native abstractions cannot yet express required teardown, gesture arbitration, or lifetime semantics.
