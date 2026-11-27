import AVFoundation
import Foundation
import Testing
@testable import HelioKit

@MainActor
struct VideoPlayerHolderTests {
  private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0 ..< 100 where !condition() {
      try? await Task.sleep(for: .milliseconds(50))
    }
  }

  @Test func reloadsAFailedItemAFewTimesThenStops() async {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).mp4")
    let holder = VideoPlayerHolder(url: missing)
    #expect(holder.player != nil)
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

  @Test func buildsMultivariantPlaylistFromRedditDASHManifest() throws {
    let dash = """
    <MPD xmlns="urn:mpeg:dash:schema:mpd:2011">
      <Period id="0">
        <AdaptationSet contentType="video" id="1">
          <Representation bandwidth="801396" codecs="avc1.4d401e" frameRate="15360/512" height="640" id="8" mimeType="video/mp4" width="360">
            <BaseURL>CMAF_360.mp4</BaseURL>
          </Representation>
          <Representation bandwidth="2266962" codecs="avc1.4d401f" frameRate="30" height="1280" id="10" mimeType="video/mp4" width="720">
            <BaseURL>CMAF_720.mp4</BaseURL>
          </Representation>
        </AdaptationSet>
        <AdaptationSet contentType="audio" id="2">
          <Representation bandwidth="69089" codecs="mp4a.40.2" id="12" mimeType="audio/mp4">
            <BaseURL>CMAF_AUDIO_64.mp4</BaseURL>
          </Representation>
          <Representation bandwidth="143944" codecs="mp4a.40.2" id="13" mimeType="audio/mp4">
            <BaseURL>CMAF_AUDIO_128.mp4</BaseURL>
          </Representation>
        </AdaptationSet>
      </Period>
    </MPD>
    """
    let baseURL = try #require(URL(string: "https://v.redd.it/abc123/"))
    let manifest = try #require(RedditVideoPlaylistRecovery.buildMultivariantPlaylist(fromDASHData: Data(dash.utf8), baseURL: baseURL))

    #expect(manifest.contains("#EXTM3U"))
    #expect(manifest.contains("URI=\"https://v.redd.it/abc123/CMAF_AUDIO_128.m3u8\""))
    #expect(manifest.contains("DEFAULT=YES,AUTOSELECT=YES,URI=\"https://v.redd.it/abc123/CMAF_AUDIO_128.m3u8\""))
    #expect(manifest.contains("DEFAULT=NO,AUTOSELECT=NO,URI=\"https://v.redd.it/abc123/CMAF_AUDIO_64.m3u8\""))
    #expect(manifest.contains("RESOLUTION=360x640,FRAME-RATE=30,CODECS=\"avc1.4d401e,mp4a.40.2\",AUDIO=\"audio\""))
    #expect(manifest.contains("https://v.redd.it/abc123/CMAF_360.m3u8"))
    #expect(manifest.contains("https://v.redd.it/abc123/CMAF_720.m3u8"))
  }

  @Test func buildsVideoOnlyPlaylistWhenDASHHasNoAudio() throws {
    let dash = """
    <MPD xmlns="urn:mpeg:dash:schema:mpd:2011">
      <Period id="0">
        <AdaptationSet contentType="video" id="1">
          <Representation bandwidth="500000" codecs="avc1.4d401e" height="480" id="1" mimeType="video/mp4" width="270">
            <BaseURL>CMAF_270.mp4</BaseURL>
          </Representation>
        </AdaptationSet>
      </Period>
    </MPD>
    """
    let baseURL = try #require(URL(string: "https://v.redd.it/silent1/"))
    let manifest = try #require(RedditVideoPlaylistRecovery.buildMultivariantPlaylist(fromDASHData: Data(dash.utf8), baseURL: baseURL))

    #expect(!manifest.contains("#EXT-X-MEDIA:"))
    #expect(!manifest.contains("AUDIO="))
    #expect(manifest.contains("https://v.redd.it/silent1/CMAF_270.m3u8"))
  }

  @Test func fallsBackToMP4WhenDASHRecoveryFails() async throws {
    let hls = try #require(URL(string: "https://v.redd.it/abc123/HLSPlaylist.m3u8"))
    let dash = try #require(URL(string: "https://v.redd.it/abc123/DASHPlaylist.mpd?a=sig"))
    let fallback = try #require(URL(string: "https://v.redd.it/abc123/CMAF_720.mp4?source=fallback"))
    let recovered = await RedditVideoPlaylistRecovery.recover(
      hlsURL: hls,
      dashURL: dash,
      fallbackURL: fallback,
      fetch: { _ in throw URLError(.badServerResponse) },
    )
    #expect(recovered == .directURL(fallback))
  }

  @Test func reloadsFailedRedditHLSWithRecoveredManifestThenStepsDownToFallback() async throws {
    let hls = try #require(URL(string: "https://v.redd.it/abc123/HLSPlaylist.m3u8"))
    let fallback = try #require(URL(string: "https://v.redd.it/abc123/CMAF_720.mp4?source=fallback"))
    let manifest = "#EXTM3U\n#EXT-X-VERSION:4\n"
    let holder = VideoPlayerHolder(
      url: hls,
      fallbackURL: fallback,
      recoverPlaylist: { _, _, _ in .manifest(manifest, sourceURL: hls) },
    )
    var replaced = false
    #expect(holder.reload { replaced = true })
    await waitUntil { replaced }
    #expect(replaced)
    let recoveredAsset = holder.player?.currentItem?.asset as? AVURLAsset
    #expect(recoveredAsset?.url.scheme == RedditVideoPlaylistRecovery.customScheme)
    #expect(recoveredAsset?.resourceLoader.delegate != nil)

    #expect(holder.reload())
    let fallbackAsset = holder.player?.currentItem?.asset as? AVURLAsset
    #expect(fallbackAsset?.url == fallback)
  }

  @Test func coalescesConcurrentReloadsWhileDASHRecoveryIsInFlight() async throws {
    let hls = try #require(URL(string: "https://v.redd.it/abc123/HLSPlaylist.m3u8"))
    let fallback = try #require(URL(string: "https://v.redd.it/abc123/CMAF_720.mp4?source=fallback"))
    let manifest = "#EXTM3U\n#EXT-X-VERSION:4\n"
    var recoveryContinuation: CheckedContinuation<RedditVideoPlaylistRecovery.RecoveredSource?, Never>?
    var recoveryCalls = 0
    let holder = VideoPlayerHolder(
      url: hls,
      fallbackURL: fallback,
      recoverPlaylist: { _, _, _ in
        await MainActor.run { recoveryCalls += 1 }
        return await withCheckedContinuation { continuation in
          Task { @MainActor in recoveryContinuation = continuation }
        }
      },
    )

    var firstReplaced = false
    var secondReplaced = false
    #expect(holder.reload { firstReplaced = true })
    await waitUntil { recoveryContinuation != nil }
    #expect(holder.reload { secondReplaced = true })
    #expect(recoveryCalls == 1)

    recoveryContinuation?.resume(returning: .manifest(manifest, sourceURL: hls))
    await waitUntil { firstReplaced && secondReplaced }
    #expect(firstReplaced && secondReplaced)

    #expect(holder.reload())
    let fallbackAsset = holder.player?.currentItem?.asset as? AVURLAsset
    #expect(fallbackAsset?.url == fallback)
  }

  @Test func lightboxDoesNotRestartVideoPausedDuringDASHRecovery() async throws {
    let hls = try #require(URL(string: "https://v.redd.it/abc123/HLSPlaylist.m3u8"))
    let manifest = "#EXTM3U\n#EXT-X-VERSION:4\n"
    var recoveryContinuation: CheckedContinuation<RedditVideoPlaylistRecovery.RecoveredSource?, Never>?
    let holder = VideoPlayerHolder(
      url: hls,
      recoverPlaylist: { _, _, _ in
        await withCheckedContinuation { continuation in
          Task { @MainActor in recoveryContinuation = continuation }
        }
      },
    )
    let video = LightBoxVideo(video: SharedVideo(url: hls, size: CGSize(width: 720, height: 1280)), holder: holder)
    video.activate()
    video.retry()
    await waitUntil { recoveryContinuation != nil }

    video.togglePlayback()
    #expect(video.player?.timeControlStatus == .paused)

    recoveryContinuation?.resume(returning: .manifest(manifest, sourceURL: hls))
    await waitUntil { (video.player?.currentItem?.asset as? AVURLAsset)?.url.scheme == RedditVideoPlaylistRecovery.customScheme }
    #expect(video.player?.timeControlStatus == .paused)
    video.release()
  }
}
