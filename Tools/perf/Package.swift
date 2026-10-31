// swift-tools-version: 6.0
// `perf`: measures Helio in the iOS simulator against fixture Reddit data. See README.md.

import PackageDescription

let package = Package(
  name: "perf",
  platforms: [.macOS(.v15)],
  targets: [
    .executableTarget(name: "perf", exclude: []),
    .testTarget(name: "PerfTests", dependencies: ["perf"]),
  ],
  swiftLanguageModes: [.v5],
)
