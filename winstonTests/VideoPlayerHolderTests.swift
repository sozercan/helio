import AVFoundation
import Foundation
import Testing
@testable import winston

@MainActor
struct VideoPlayerHolderTests {
  private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<100 where !condition() {
      try? await Task.sleep(for: .milliseconds(50))
    }
  }

  @Test func reloadsAFailedItemAFewTimesThenStops() async {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).mp4")
    let holder = VideoPlayerHolder(url: missing)
    await waitUntil { holder.hasFailed }
    #expect(holder.hasFailed)
    #expect(!holder.isReadyToPlay)

    let firstItem = holder.player?.currentItem
    #expect(holder.reload())
    #expect(holder.player?.currentItem !== firstItem)
    #expect(holder.reload())
    #expect(!holder.reload())
  }

  @Test func holderWithoutAURLHasNoPlayer() {
    let holder = VideoPlayerHolder(url: nil)
    #expect(holder.player == nil)
    #expect(!holder.reload())
  }
}
