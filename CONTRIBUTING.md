# Contributing to Helio

Pull requests are welcome against `main`. Please open an issue first for larger changes.

Coding agents should also read [`AGENTS.md`](AGENTS.md), which has more detail on the project's conventions.

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

Existing SwiftLint violations are recorded in `.swiftlint.baseline.json`, so only new ones fail. When you fix old ones, regenerate it with `swiftlint lint --write-baseline .swiftlint.baseline.json`.

To keep `git blame` from showing the bulk formatting commit, run `git config blame.ignoreRevsFile .git-blame-ignore-revs`.

Add dependencies in `Package.swift`, not in the Xcode project. Asset catalog symbols used from `HelioKit` (e.g. `Image(.loader)`) are declared in `Sources/HelioKit/globals/AppAssets.swift`.

## Releases

To release, push a version tag (`git tag v1.7.0 && git push origin v1.7.0`). The release workflow builds the unsigned IPA and the Mac app, publishes the GitHub release and adds the version to the source feed on `gh-pages`. Run it manually from the Actions tab for a dry run that only builds.
