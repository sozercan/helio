// swift-tools-version: 6.0

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
