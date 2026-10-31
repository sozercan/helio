# Helio

[![Build](https://github.com/sozercan/helio/actions/workflows/build.yml/badge.svg)](https://github.com/sozercan/helio/actions/workflows/build.yml)
![License](https://img.shields.io/github/license/sozercan/helio)
[![Platform](http://img.shields.io/badge/platform-iOS/iPadOS-blue.svg)](https://developer.apple.com/iphone/index.action)
![GitHub issues](https://img.shields.io/github/issues-raw/sozercan/helio)
![GitHub release](https://img.shields.io/github/v/release/sozercan/helio)

Helio is a privacy-focused, open-source Reddit client for iOS and Mac. No analytics, no tracking, no ads, no third-party data collection — your data stays on your device and your account talks only to Reddit. It builds on [Winston](https://github.com/lo-cafe/winston) by the lo.cafe team and its community.

## Privacy

- **No analytics or tracking** — zero telemetry, no usage data collected
- **No ads or ad networks** — no advertising SDKs of any kind
- **No third-party data collection** — no third-party SDKs or services
- **Your account talks only to Reddit** — sign-in and every account request go to Reddit's OAuth and API endpoints. Images, videos and link previews load from the sites that host them, as they would in a browser.
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

## Links

- [Report a bug](https://github.com/sozercan/helio/issues)
- [Contributing](CONTRIBUTING.md)

## Credits

Helio is free and open source software. It builds on [Winston](https://github.com/lo-cafe/winston) by the lo.cafe team and its community.

## License

Helio is open-source, licensed under the GPL-3.0 license. See the LICENSE file for details.
