# Architecture Decision Records

Non-obvious architectural, protocol, privacy, performance, and platform decisions for Helio live here rather than in inline code comments.

| ADR | Area |
| --- | --- |
| [0001-navigation-and-adaptive-layout.md](0001-navigation-and-adaptive-layout.md) | Navigation, WindowMetrics, iPhone Duo, keyboard commands, Quick Actions |
| [0002-reddit-api-auth-and-privacy.md](0002-reddit-api-auth-and-privacy.md) | Reddit API, keyless web-session auth, OAuth, cookie isolation, decoding safeguards |
| [0003-feed-comment-loading-and-caching.md](0003-feed-comment-loading-and-caching.md) | Feed/comment loading, `FeedItemsManager`, caching, Core Data persistence |
| [0004-media-rendering-and-lightbox.md](0004-media-rendering-and-lightbox.md) | Media resolution, Nuke decoding, video playback, lightbox gestures |
| [0005-swiftui-performance-and-view-identity.md](0005-swiftui-performance-and-view-identity.md) | SwiftUI identity, `@Observable`, `CachedDefaults`, list insertion, relayout |
| [0006-mac-catalyst-and-updater.md](0006-mac-catalyst-and-updater.md) | Mac Catalyst toolbar/sidebar, in-app web views, web extensions, Sparkle updater |
| [0007-theming-and-visual-components.md](0007-theming-and-visual-components.md) | Theming, shaders, swipe actions, markdown rendering, UI components |
| [0008-testing-tooling-and-performance-harness.md](0008-testing-tooling-and-performance-harness.md) | Unit/UI tests, `Tools/perf` benchmark harness, CI scripts, package layout |
