# ADR-0006: Mac Catalyst Toolbar, In-App Web View, Web Extensions, and Sparkle Updater

Status: Accepted

## Context

Running Helio as a native-feeling Mac Catalyst app alongside iOS/iPadOS introduces platform constraints that standard UIKit/SwiftUI APIs do not cover out of the box:

- A split-view sidebar shifts leading and centered `NSToolbar` items when switching tabs, and modal sheets do not disable toolbar validation automatically.
- `SFSafariViewController` leaves the app on Mac, covers both columns on iPad/iPhone Duo, and cannot run user-installed WebKit web extensions.
- WebKit's `WKWebExtension` runtime cannot unload extensions until relaunch, refuses to run in ephemeral/non-persistent data stores, and requires a browser window/tab host abstraction.
- Sparkle is an AppKit framework that Mac Catalyst cannot link directly, while Helio's privacy model requires update checks to be strictly opt-in and cryptographically verified on ad-hoc signed Mac builds.

This ADR documents the architectural decisions and platform invariants for Mac Catalyst window chrome, `WebPageScreen`, the WebExtensions runtime/store, and the Sparkle updater bridge.

## Decisions

### Mac Catalyst Window Toolbar

Implemented in `Sources/HelioKit/views/Tabber/MacTabToolbar.swift`:

- **Trailing-aligned tabs, hidden window title, and column-aligned actions**: When the Posts tab shows its split-view sidebar, the window toolbar begins after the sidebar, which shifts leading or centered items horizontally on tab switches. Pinning the tab switcher to the trailing edge (which never moves) and hiding the window title prevents horizontal jumping, while `Tabber` hides UIKit's tab bar on Mac. The Posts tab uses the standard leading Mac sidebar button instead of SwiftUI's button inside the subscriptions list. Per-screen actions (sort, filters, subreddit info, account switcher) register with `CommandTargets` and live in the window toolbar above their owning split-view column (after the split view's tracking separators) rather than in a navigation bar below the toolbar.
- **Overflow priority and expanded tab representation**: Screen actions use `.low` visibility priority so they spill into the overflow menu first in narrow windows. The tab switcher uses `.user` priority and sets `controlRepresentation` via KVC (an AppKit property absent from Catalyst headers that the toolbar item group still responds to) so tabs remain tabs instead of collapsing into a pop-up button.
- **Diff-based reconfiguration and dynamic menu dispatch**: Toolbar items are reconfigured only when their visible appearance changes, avoiding repeated toolbar relayouts and menu rebuilds on every screen state update. Buttons and menu items resolve the live `ScreenAction` at invocation time—menu items dispatch by index path (`path`) into the item's current action—so cached `UIMenu` instances stay valid without rebuilding when only closure captures change.
- **Manual validation under modal coverage**: Modal reply sheets leave the toolbar clickable around them, and AppKit's automatic toolbar validation would re-enable items that have a target and action. `autovalidates` is therefore disabled and `isEnabled` is managed manually (matching menu bar behavior), reading only the observable part of `CommandTargets.isCovered()` (reply, full-screen viewer, or app sheet) so observation tracking updates the toolbar when modal coverage changes.

### In-App Web View (`WebPageScreen`)

Implemented in `Sources/HelioKit/views/WebPageScreen.swift`:

- **Routing links to `WebPageScreen` instead of `SFSafariViewController`**: Links from feeds and posts (`Nav.openLink`) open in `WebPageScreen` on Mac (where Safari's view would leave the app), in multi-column layouts beside the feed on iPad and open iPhone Duo (where a Safari sheet would cover both columns), and on any platform whenever at least one web extension is enabled (since Safari's view runs none of the app's extensions).
- **Dedicated launch-cleared persistent data store (`WebPageStorage`)**: Web pages use a dedicated `WKWebsiteDataStore` with a fixed UUID—isolated from the Reddit sign-in store and cleared on every launch. It is intentionally on-disk rather than non-persistent/in-memory (`isPrivate` returns `false`) because WebKit refuses to run web extensions in non-persistent stores. The fixed UUID ensures every launch locates and wipes the previous launch's cookies, storage, and cache.
- **Startup ordering barrier**: `WebPageModel` creation awaits `WebExtensionRuntime.shared.start()`, guaranteeing that a link opened immediately after launch cannot race ahead of previous-launch storage clearing or extension loading.
- **Safe `WKWebView` lease handoff and reparenting (`PageView`)**:
  - `PageView` waits for `lease.settled` before mounting so a transient screen cannot steal a live `WKWebView` from another screen.
  - `PageView` wraps the `WKWebView` in a dedicated container `UIView` rather than returning the `WKWebView` directly as the representable's view, preventing an outgoing layout's teardown from detaching a web view already handed over to a new screen.
  - `updateUIView` attaches the `WKWebView` only when `superview == nil`, preventing a dying screen's update pass from reclaiming it from the new screen.
  - The unloaded branch renders `Color.clear` instead of an empty `Group`, because an empty SwiftUI `Group` never triggers `onAppear`/`task` and the page would never be constructed.
- **Navigation security and `target="_blank"` handling**:
  - External-app URL schemes (such as `mailto:`) are forwarded only for user-activated main-frame clicks; pages cannot launch other apps via redirects, scripts, or subframes.
  - `webkit-extension:` URLs may load in frames, but not as top-level page navigations, because WebKit only loads extension pages in a `WKWebView` created from the extension's own `WKWebViewConfiguration`.
  - `target="_blank"` links load in place because there is no secondary window to host a new `WKWebView`.
- **Chrome, contrast, and safe-area presentation**:
  - `PageView` ignores the bottom safe area because `WKWebView` already insets for the home indicator; staying inside the safe area leaves a black band beneath the page.
  - The navigation bar uses an opaque `.systemBackground` because the bar follows the app's appearance while the page follows its own, which otherwise left unreadable white bar text over light pages in dark mode.
  - The tab bar is hidden only when the web page fills the window (so it does not cover the page's bottom toolbar of back/forward/reload/stop controls), and remains visible beside a feed.
  - `PageToolbar` is compiled out on Mac Catalyst since those controls live in `MacTabToolbar`.

### Web Extensions Runtime, Storage, and Options UI

Implemented in `Sources/HelioKit/models/WebExtensions/WebExtensionRuntime.swift`, `Sources/HelioKit/models/WebExtensions/WebExtensionStore.swift`, and `Sources/HelioKit/views/Settings/views/WebExtensionsPanel.swift`:

- **Launch-only loading and synthetic single-window host (`WebExtensionRuntime`)**: Enabled extensions load once at launch into a shared controller used by `WebPageScreen`. Because WebKit cannot unload an extension at runtime, adding, toggling, or removing extensions takes effect on the next launch. Because WebKit requires a browser window/tab hierarchy to find a page's `WKWebView` and run scripts—and Helio has no browser tabs—each shown web page registers as a tab of one synthetic window.
- **Two-store isolation and stable extension identity (`WebExtensionRuntime`)**:
  - The controller's default data store (accessed by extensions' cookie and data APIs) is `WebPageStorage`, never the app's Reddit auth store.
  - Extensions' own pages (background, settings) use a separate persistent `WKWebsiteDataStore` identified by a fixed `extensionPagesStoreID` UUID so clearing `WebPageStorage` at launch leaves extension configuration intact.
  - Each extension's `context.uniqueIdentifier` is pinned to its persistent `id` so its storage and page origin remain stable across launches.
- **Up-front permission grants (`WebExtensionRuntime`)**: User-added extensions are granted both requested and optional permissions up front because Helio has no runtime permission-prompt UI and extensions such as uBlock Origin Lite need host access across sites to hide page elements (not just block requests).
- **Copied storage, deferred deletion, and atomic list persistence (`WebExtensionStore`)**:
  - No extensions are bundled or preinstalled. Each user-added extension is copied into `Application Support/Helio/WebExtensions` (explicitly scoped under the app's own subfolder because `Application Support` is shared across apps on macOS) so it does not depend on the original folder remaining in place, with the manifest list stored beside the copies.
  - `remove(_:)` only removes the entry from the list; folder deletion is deferred until the next launch because WebKit keeps already-loaded extensions running and reading their files for the rest of the session.
  - Orphaned extension folders are pruned at launch only when the manifest list decoded successfully, preventing accidental deletion if the list file is unreadable.
  - List updates are written atomically before mutating in-memory state so a failed write cannot diverge from what the next launch will load.
  - Whenever any extension is enabled, link routing prefers `WebPageScreen` over Safari's view so extensions actually execute.
- **Extension options pages (`WebExtensionsPanel`)**: `OptionsPage` presents an extension's settings page using the extension's own `WKWebViewConfiguration` (providing its own origin, storage, and WebExtension APIs) and attaches a `WKUIDelegate` so JavaScript `confirm()`/`alert()` dialogs (such as reset confirmations) function.

### Mac Sparkle Updater Bridge

Implemented in `Sources/HelioKit/globals/MacUpdater.swift` (bridging to `Sources/HelioMacUpdater` / `App/HelioMacUpdater`):

- **AppKit plugin loaded via Objective-C runtime**: Sparkle requires AppKit, which a Mac Catalyst app cannot link. `HelioMacUpdater.bundle` wraps Sparkle as a macOS plugin loaded at runtime and called via the Objective-C runtime.
- **Direct `IMP` call for `BOOL` return**: Because `perform(_:)` cannot return an Objective-C `BOOL`, `start` is invoked directly via `unsafeBitCast` to a typed `IMP`.
- **Opt-in privacy and EdDSA trust requirement**: Update checks contact only `appcast.xml` on GitHub Pages and download updates from GitHub Releases, and only once the user opts in (Sparkle asks on the second launch; Settings can disable checks). If the plugin bundle or EdDSA public key is missing, `updater` stays `nil` and all update UI (menu item and setting) is hidden, because Sparkle requires the EdDSA key to trust ad-hoc signed Mac builds.
- **Window-ordered startup and `UserDefaults` sync**:
  - `start()` runs once, only after the first window is visible, so Sparkle's initial permission prompt does not appear behind the main window.
  - `checksAutomatically` is re-read on `UserDefaults.didChangeNotification` because Sparkle's own permission prompt mutates the default outside Helio's UI. The `NotificationCenter` observer is intentionally never removed because `MacUpdater.shared` lives for the lifetime of the process.

## Consequences

- Mac Catalyst gains stable window toolbar geometry, column-aligned actions, and modal-safe enablement without private framework linking (aside from the KVC `controlRepresentation` hint on the toolbar item group).
- In-app browsing supports user-installed web extensions while keeping site data isolated from Reddit sign-in state and wiped on every launch.
- Extension enable/disable/remove changes require an app relaunch by WebKit design, and the `@objc` selector contract between `MacUpdater.swift` and `HelioMacUpdater` must be kept strictly in sync.
