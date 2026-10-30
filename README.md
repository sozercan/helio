# Helio

[![Build](https://github.com/sozercan/helio/actions/workflows/build.yml/badge.svg)](https://github.com/sozercan/helio/actions/workflows/build.yml)
![License](https://img.shields.io/github/license/sozercan/helio)
[![Platform](http://img.shields.io/badge/platform-iOS/iPadOS-blue.svg)](https://developer.apple.com/iphone/index.action)
![GitHub issues](https://img.shields.io/github/issues-raw/sozercan/helio)
![GitHub release](https://img.shields.io/github/v/release/sozercan/helio)

Helio is a privacy-focused, open-source Reddit client for iOS and Mac. No analytics, no tracking, no ads, no third-party data collection — your data stays on your device and the app communicates only with Reddit's API. It builds on [Winston](https://github.com/lo-cafe/winston) by the lo.cafe team and its [community forks](#credits).

## Privacy

- **No analytics or tracking** — zero telemetry, no usage data collected
- **No ads or ad networks** — no advertising SDKs of any kind
- **No third-party data collection** — removed all upstream phone-home code (ThemeStore and the lo.cafe API)
- **Communicates only with Reddit** — the only network calls are to Reddit's OAuth and API endpoints
- **Open source** — audit the code yourself

## Installing

Helio requires iOS 26+ (or macOS 26+) and your own Reddit API credentials.

**Sideload a release.** Each [release](https://github.com/sozercan/helio/releases) has an unsigned `.ipa` and a Mac `.zip`.

- iPhone and iPad: add the source `https://sozercan.github.io/helio/source.json` in [SideStore](https://sidestore.io) or [AltStore](https://altstore.io) to install and get updates, or sideload the `.ipa` with [Sideloadly](https://sideloadly.io). These tools re-sign the app with your Apple ID. With a free account the app has to be refreshed every 7 days, and the Safari extension uses a second app ID. iCloud isn't available to sideloaded apps, so data stays on the device.
- Mac: unzip, move Helio to Applications, then allow it under System Settings > Privacy & Security on first launch. The build isn't notarized and has no keychain access, so it asks you to sign in to Reddit again on each launch. Build it yourself (below) to keep the login.

**Build it yourself.**

1. Clone the repo and open `App/Helio.xcodeproj` in Xcode
2. Set your development team and bundle identifier in the project settings
3. Build and run on your device

Then follow the in-app credential setup to connect your Reddit account. Your Reddit app's redirect URI must be `https://sozercan.github.io/helio/auth-success`: Reddit only accepts https redirects for web apps, and that page (served from this repo's `gh-pages` branch) forwards to the app. If your app was created with another redirect URI, change it under "edit" at https://www.reddit.com/prefs/apps.

## Development

The app's code, dependencies and unit tests are a Swift package (`Package.swift`, `Sources/HelioKit`, `Tests/HelioKitTests`). `App/Helio.xcodeproj` is a thin shell that builds the iOS app bundle and the Safari extension on top of the `HelioKit` library. It owns the entry point (`App/Helio/HelioApp.swift`), `Info.plist`, entitlements and every resource: the asset catalog, strings, the Core Data model, shaders, Lottie animations and media. Code in `HelioKit` looks those up in `Bundle.main`.

```bash
# Build the package for the simulator
swift build --triple arm64-apple-ios26.0-simulator --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)"

# Unit tests (run from the repository root; prints a destination for an available iPhone simulator)
xcodebuild -scheme HelioKit -destination "$(.github/scripts/simulator-destination.sh)" test

# App
xcodebuild -project App/Helio.xcodeproj -scheme Helio -destination 'generic/platform=iOS Simulator' build
```

Format and lint before committing. CI runs both on every pull request and on `main`, with the tool versions pinned in `.github/workflows/lint.yml` (SwiftLint 0.65.1, SwiftFormat 0.64.0):

```bash
swiftformat . && swiftlint --strict
```

Existing SwiftLint violations are recorded in `.swiftlint.baseline.json`, so only new ones fail. When you fix old ones, regenerate it with `swiftlint lint --write-baseline .swiftlint.baseline.json`. To release, push a version tag (`git tag v1.7.0 && git push origin v1.7.0`). The release workflow builds the unsigned IPA and the Mac app, publishes the GitHub release and adds the version to the source feed on `gh-pages`. Run it manually from the Actions tab for a dry run that only builds.

To keep `git blame` from showing the bulk formatting commit, run `git config blame.ignoreRevsFile .git-blame-ignore-revs`.

Add dependencies in `Package.swift`, not in the Xcode project. Asset catalog symbols used from `HelioKit` (e.g. `Image(.loader)`) are declared in `Sources/HelioKit/globals/AppAssets.swift`.

## Changes from upstream

- Fixed broken tab bar (buttons not responding to taps)
- Fixed scroll jumping when loading new content
- Fixed post text truncation
- Fixed startup blur race condition
- Fixed cross-tab navigation (e.g. "Go to credentials settings")
- Auto-select credentials after first setup
- OAuth redirect via custom URL scheme (no dependency on lo.cafe servers)
- Updated branding, FAQ, and links for this fork
- Replaced CI with simple build + release workflows
- Fixed duplicate subreddits in the subs list
- Removed ThemeStore and lo.cafe API third-party phone-home code
- Added dark mode / light mode / system appearance setting
- Fixed feed switching error when navigating between Home/Popular/All/Saved
- Auto build numbers from git commit count
- Fixed video playback breaking after scrolling past many videos (leaked AVPlayer view controllers were exhausting iOS's limited video decode pipelines; previously only a force-restart recovered it)
- Added text selection on post body text (long-press to select, Look Up, Copy, Share)

## Contributing

Pull requests welcome against `main`. Please open an issue first for larger changes.

## Links

- [Report a bug](https://github.com/sozercan/helio/issues)

## Credits

Helio is free and open source software. It builds on [Winston](https://github.com/lo-cafe/winston) by the lo.cafe team and its community forks:

- [phubbard/winston](https://github.com/phubbard/winston)
- [eliburke/winston](https://github.com/eliburke/winston)
- [d0lb33/winston](https://github.com/d0lb33/winston)

## License

Helio is open-source, licensed under the GPL-3.0 license. See the LICENSE file for details.
