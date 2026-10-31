# AGENTS.md

Guidance for coding agents working in this repository. `CLAUDE.md` is a symlink to this file.

Helio is a privacy-focused Reddit client for iPhone, iPad and Mac (Mac Catalyst), written in SwiftUI. It targets iOS 26+ and Mac Catalyst 26+.

## Project layout

- `Package.swift`, `Sources/HelioKit`, `Tests/HelioKitTests`: the app's code, dependencies and unit tests, as a Swift package. Tools version 6.2, Swift 5 language mode.
- `App/Helio.xcodeproj`: a thin shell that builds the app bundle and the Safari extension on top of `HelioKit`. It owns the entry point (`App/Helio/HelioApp.swift`), `Info.plist`, entitlements and every resource: asset catalog, `App/Localizable.xcstrings`, the Core Data model, shaders, Lottie animations and media.
- Because resources live in the app bundle, `HelioKit` code looks them up in `Bundle.main`. Asset catalog symbols used from `HelioKit` (such as `Image(.loader)`) are declared by hand in `Sources/HelioKit/globals/AppAssets.swift`; add new ones there.
- Add dependencies in `Package.swift`, never in the Xcode project.
- `App/helio-everywhere` is the Safari extension. Its built bundle in `dist/` is committed and is what the app embeds, so after changing `src/`, run `npm run build` in that directory and commit `dist/` with the change. The extension target's Resources phase lists each `dist/` file by its hashed name, so if the build adds, removes or renames files, update the file references and Resources phase in `App/Helio.xcodeproj` to match and delete the stale files.
- `App/HelioUITests` is not a synced folder: a new test file must also be added to the target in the project file.

## Build, test, lint

```bash
# Build the package for the simulator (fastest compile check)
swift build --triple arm64-apple-ios26.0-simulator --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)"

# Unit tests, from the repo root
xcodebuild -scheme HelioKit -destination "$(.github/scripts/simulator-destination.sh)" test

# App, iOS and Mac Catalyst (CI builds both)
xcodebuild -project App/Helio.xcodeproj -scheme Helio -destination 'generic/platform=iOS Simulator' build
xcodebuild -project App/Helio.xcodeproj -scheme Helio -destination 'generic/platform=macOS,variant=Mac Catalyst' CODE_SIGNING_ALLOWED=NO build

# Format and lint before committing
swiftformat . && swiftlint --strict
```

- Get simulator destinations from `.github/scripts/simulator-destination.sh` instead of hard-coding a device name; simulator names change with each Xcode release.
- CI pins Xcode 26.6 (Swift 6.3), SwiftLint 0.65.1 and SwiftFormat 0.64.0. A local Xcode is often newer, so code that builds locally can still fail in CI. Two recurring cases:
  - APIs from the 27 SDK need `#if compiler(>=6.4)` around the `#available` check (see `Sources/HelioKit/views/Tabber/MacTabToolbar.swift`).
  - Swift 6.3's type checker gives up on some expressions newer compilers accept, such as a ternary of `.upvote`/`.downvote` passed to `foregroundStyle`. Spell out the type (`Color.upvote`) when it's ambiguous.
- Existing SwiftLint violations are recorded in `.swiftlint.baseline.json`, so `--strict` fails only on new ones. After fixing old ones, regenerate it with `swiftlint lint --write-baseline .swiftlint.baseline.json`. Don't apply SwiftLint autocorrect to `let _ =` inside SwiftUI view or `ViewModifier` bodies; it's the only form a ViewBuilder accepts.
- Formatting is 2-space indentation with implicit `self`; `.swiftformat` documents the disabled rules and why.
- `perf.yml` runs `Tools/perf` on PRs that touch the app and fails when it makes more Reddit API requests than `Tools/perf/budget.json` allows. For changes to networking or feed and comment rendering, follow the `helio-perf` skill (`.agents/skills/helio-perf/SKILL.md`) and report before/after numbers; lower the budget when request counts drop.

## Privacy and Reddit API

Privacy is the app's main promise, so these hold unless the human explicitly changes them:

- The app's own services are Reddit's OAuth and API endpoints and nothing else. Don't add analytics, crash reporting, ad SDKs, or any app-level backend.
- Loading the content a post points to is expected: images and video from their hosts, link-preview metadata from the linked page (`PreviewModel`), and hosts such as Streamable or YouTube to resolve and play embeds. Keep those requests limited to content the user is viewing, and don't send them account data or identifiers.
- Use Reddit's OAuth REST API (`oauth.reddit.com`). Don't use Reddit's private GraphQL API.
- The default sign-in needs no API key (`RedditWebSession`, `RedditWebLoginView`): the user signs in on reddit.com in an in-app browser with its own empty cookie store, Helio keeps that session's reddit.com cookies in the keychain, and it trades them for bearer tokens at `accounts.reddit.com/api/access_token` with the public client id of Reddit's mobile site. That id is the only real Reddit client id allowed in code. Session cookies go only to reddit.com, never into the shared cookie store or logs. This is outside Reddit's published API terms, so a user's own API key stays available as the opt-in alternative.
- Never put real Reddit secrets, refresh tokens, session cookies, usernames or other client IDs in code, tests, fixtures, logs, commits or PR text. Use obvious placeholders.
- The OAuth redirect for API-key credentials is `https://sozercan.github.io/helio/auth-success`, a static page on the `gh-pages` branch that forwards to `helioapp://auth-success`. Reddit requires an https redirect for web-app keys, so a bare `helioapp://` redirect breaks login.
- Reddit entity ids in the models have the kind appended (`"abc"` + `"t1"`). Compare `data.id` when matching Reddit ids.

## Code conventions

- Layout reads `WindowMetrics` (window size, content width, width class), never `UIScreen.main.bounds` or `userInterfaceIdiom`. The window changes size at runtime: iPad multitasking, Mac window resizing, and folding or unfolding the iPhone Duo, whose folded state puts a vertical tab bar on the right. SwiftLint warns on the banned APIs.
- New observable models use `@Observable`, not `ObservableObject`.
- Use Swift concurrency instead of `DispatchQueue`, `os.Logger` instead of `print()`, `NavigationStack`/`NavigationSplitView` instead of `NavigationView`, and `.foregroundStyle` instead of `.foregroundColor`. `.swiftlint.yml` enforces these.
- New unit tests use Swift Testing (`@Test`, `#expect`).
- Feeds load through `FeedItemsManager`, and every fetch has to end in a visible state: items, empty, end of feed, or the error row with its reload button. Never set `displayMode` to `.loading` unless a fetch that will replace it is on its way. Reload with `fetchCaller(loadingMore: false)`, which drops pages still in flight from older fetches, rather than fetching another way.
- Listings decode item by item: an item Reddit sends in an unexpected shape is skipped and logged under the `Listing` category instead of failing the page. When posts go missing, look there before loosening a model. Code that treats a listing as the complete set, such as the subscription sync that deletes whatever is missing, must check `ListingData.skippedChildren` and fail instead.
- On Mac, the tab bar is a native `NSToolbar` (`MacTabToolbar`) at the top of the window, not the iOS tab bar or a sidebar-adaptable tab view. The subs sidebar uses the window background with a hairline divider; avoid glass capsules or a sidebar shade that differs from the title bar.

## Running the app

- Without Reddit credentials, only Settings is reachable in the simulator; the other tabs show "No credential". `Tools/perf` drives a scripted benchmark on seeded fixture data with a placeholder account (see its `README.md`); it isn't a way to try a UI change by hand. Say so when a UI change couldn't be checked for lack of an account rather than implying it was.
- An unprovisioned Mac Catalyst build (ad-hoc or "Sign to Run Locally") gets `errSecMissingEntitlement` for every keychain call, so it forgets the Reddit login on each launch. To keep the login, build with automatic signing, `-allowProvisioningUpdates`, a development team, and an entitlements file outside the repo that contains only `keychain-access-groups` = `$(AppIdentifierPrefix)com.sertacozercan.helio`. Don't commit signing changes to the project.

## Review

For non-trivial code changes, run the vendored autoreview skill (`.agents/skills/autoreview/SKILL.md`) before you commit, push or report the work as done. Run it without being asked, and repeat it until it has no accepted findings. Skip it for docs-only or trivial changes, when an equivalent review already ran on the same diff, or when the human opts out.

```bash
AUTOREVIEW=.agents/skills/autoreview/scripts/autoreview
python3 "$AUTOREVIEW" --mode local --max-priority P1                         # uncommitted work
python3 "$AUTOREVIEW" --mode branch --base <PR base ref> --max-priority P1   # committed branch
```

- Use `--max-priority P1`. The skill's default accepts only P0 blockers, which would pass a broken Mac layout or a tab whose state stops updating. P2 and P3 are mostly minor issues and nits that would keep the repeat-until-clean loop going without making the app better; they still appear in the audit output.
- Read the skill and its `references/diagnostics-and-results.md` before the first run; they cover targets, engines and how to read the result.
- PRs here are often stacked, so pass the PR's actual base branch, not `main`, or the review covers the lower PRs' commits too.
- Findings are advice. Check each against the real code path before changing anything, and say which ones you rejected and why.
- Format before reviewing, since formatting moves line numbers. If review fixes change code, rerun the focused tests and the review.
- The copy here is vendored from `sozercan/skills` (`skills/autoreview`). Change shared behavior there and re-copy `SKILL.md`, `references/` and `scripts/`, keeping the `LICENSE` beside them; keep Helio-specific review rules in this file.

## Git and releases

- The repository is `sozercan/helio`, a standalone repo with no upstream. Open PRs against its `main`.
- Commits use Conventional Commits with a sign-off (`git commit -s`). Subjects describe the user-visible behavior in plain words, such as `fix: show tall images whole instead of cropping them`; the body explains why.
- Pushing a `v*` tag runs `release.yml`, which publishes the unsigned IPA and Mac zip and updates the sideload feed on `gh-pages`. Don't tag a release unless asked.
