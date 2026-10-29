// swift-tools-version: 6.2
// The app's code, dependencies and unit tests. Helio.xcodeproj is a thin shell that builds
// the iOS app bundle (entry point, Info.plist, entitlements, resources) and the Safari
// extension on top of the HelioKit library.

import PackageDescription

let package = Package(
  name: "Helio",
  defaultLocalization: "en",
  platforms: [
    .iOS("26.0"),
    .macCatalyst("26.0"),
  ],
  products: [
    .library(name: "HelioKit", targets: ["HelioKit"]),
  ],
  dependencies: [
    .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.0.0"),
    .package(url: "https://github.com/ImTheSquid/AlertToast.git", branch: "master"),
    .package(url: "https://github.com/Tunous/DebouncedOnChange.git", from: "1.0.0"),
    .package(url: "https://github.com/sindresorhus/Defaults", from: "8.2.0"),
    .package(url: "https://github.com/kaishin/Gifu.git", exact: "3.2.2"),
    .package(url: "https://github.com/kyle-n/HighlightedTextEditor", from: "2.0.0"),
    .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", branch: "master"),
    .package(url: "https://github.com/airbnb/lottie-spm.git", from: "4.3.4"),
    .package(url: "https://github.com/kean/Nuke.git", from: "12.0.0"),
    .package(url: "https://github.com/satoshi-takano/OpenGraph.git", from: "1.0.0"),
    .package(url: "https://github.com/aheze/Popovers", from: "1.0.0"),
    .package(url: "https://github.com/EmergeTools/Pow", from: "1.0.3"),
    .package(url: "https://github.com/raymondjavaxx/SmoothGradient.git", from: "1.0.0"),
    .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.3.0"),
    .package(url: "https://github.com/malcommac/SwiftDate.git", from: "7.0.0"),
    .package(url: "https://github.com/haoking/SwiftyUI.git", from: "1.8.0"),
    .package(url: "https://github.com/xnth97/SymbolPicker.git", from: "1.0.0"),
    .package(url: "https://github.com/SvenTiigi/WhatsNewKit.git", from: "2.1.0"),
    .package(url: "https://github.com/dkk/WrappingHStack", from: "2.2.11"),
    .package(url: "https://github.com/SvenTiigi/YouTubePlayerKit.git", from: "1.0.0"),
    .package(url: "https://github.com/marmelroy/Zip.git", from: "2.0.0"),
  ],
  targets: [
    // Everything but the app entry point. Resources (asset catalog, strings, Core Data model,
    // shaders, Lottie animations, media) stay in the app bundle, so lookups use Bundle.main.
    .target(
      name: "HelioKit",
      dependencies: [
        .product(name: "Alamofire", package: "Alamofire"),
        .product(name: "AlertToast", package: "AlertToast"),
        .product(name: "DebouncedOnChange", package: "DebouncedOnChange"),
        .product(name: "Defaults", package: "Defaults"),
        .product(name: "Gifu", package: "Gifu"),
        .product(name: "HighlightedTextEditor", package: "HighlightedTextEditor"),
        .product(name: "KeychainAccess", package: "KeychainAccess"),
        .product(name: "Lottie", package: "lottie-spm"),
        .product(name: "Nuke", package: "Nuke"),
        .product(name: "NukeExtensions", package: "Nuke"),
        .product(name: "NukeUI", package: "Nuke"),
        .product(name: "NukeVideo", package: "Nuke"),
        .product(name: "OpenGraph", package: "OpenGraph"),
        .product(name: "Popovers", package: "Popovers"),
        .product(name: "Pow", package: "Pow"),
        .product(name: "SmoothGradient", package: "SmoothGradient"),
        .product(name: "MarkdownUI", package: "swift-markdown-ui"),
        .product(name: "SwiftDate", package: "SwiftDate"),
        .product(name: "SwiftyUI", package: "SwiftyUI"),
        .product(name: "SymbolPicker", package: "SymbolPicker"),
        .product(name: "WhatsNewKit", package: "WhatsNewKit"),
        .product(name: "WrappingHStack", package: "WrappingHStack"),
        .product(name: "YouTubePlayerKit", package: "YouTubePlayerKit"),
        .product(name: "Zip", package: "Zip"),
      ],
      swiftSettings: [
        .enableUpcomingFeature("BareSlashRegexLiterals"),
      ]
    ),
    .testTarget(
      name: "HelioKitTests",
      dependencies: [
        "HelioKit",
        .product(name: "Defaults", package: "Defaults"),
        .product(name: "Zip", package: "Zip"),
      ]
    ),
  ],
  swiftLanguageModes: [.v5]
)
