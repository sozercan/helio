import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import HelioKit

struct MediaScrubTests {
  @Test func aSwipeAcrossTheWindowSpansAShortClip() {
    #expect(MediaScrub.time(from: 0, translation: 400, width: 400, duration: 8) == 8)
    #expect(MediaScrub.time(from: 4, translation: -100, width: 400, duration: 8) == 2)
  }

  @Test func aLongVideoMovesAMinutePerWidth() {
    #expect(MediaScrub.time(from: 300, translation: 200, width: 400, duration: 600) == 330)
  }

  @Test func theTimeStaysInsideTheClip() {
    #expect(MediaScrub.time(from: 1, translation: -400, width: 400, duration: 8) == 0)
    #expect(MediaScrub.time(from: 7, translation: 400, width: 400, duration: 8) == 8)
  }

  @Test func anUnknownLengthLeavesThePlayheadAlone() {
    #expect(MediaScrub.time(from: 3, translation: 400, width: 400, duration: 0) == 3)
  }

  @Test func labelsShowHoursOnlyForLongVideos() {
    #expect(MediaScrub.label(3, of: 10) == "0:03 / 0:10")
    #expect(MediaScrub.label(65, of: 3700) == "0:01:05 / 1:01:40")
  }

  @Test func framesStartWhereThePreviousOnesEnd() {
    let timeline = GIFTimeline(delays: [0.5, 0.25, 0.25])
    #expect(timeline.starts == [0, 0.5, 0.75])
    #expect(timeline.duration == 1)
    #expect(timeline.frame(at: 0) == 0)
    #expect(timeline.frame(at: 0.49) == 0)
    #expect(timeline.frame(at: 0.5) == 1)
    #expect(timeline.frame(at: 0.9) == 2)
    #expect(timeline.frame(at: 1) == 2)
  }

  @Test func framesWithoutADelayShowForATenthOfASecond() {
    let timeline = GIFTimeline(delays: [0, 0.01, 0.2])
    #expect(timeline.starts == [0, 0.1, 0.2])
    #expect(abs(timeline.duration - 0.4) < 0.0001)
  }

  @MainActor
  @Test func aGIFScrubsByItsFrameTimes() throws {
    let view = try ScrubbableGIFView(data: Self.gif(delays: [0.5, 0.5, 1]))
    #expect(view.timeline.starts == [0, 0.5, 1])
    #expect(view.intrinsicContentSize == CGSize(width: 4, height: 2))
    #expect(view.beginScrub())
    let position = view.scrub(translation: 300, width: 400)
    #expect(position.time == 1.5)
    #expect(position.duration == 2)
    view.endScrub()
    #expect(!view.isScrubbing)
  }

  @MainActor
  @Test func aStillGIFDoesNotScrub() throws {
    #expect(try !ScrubbableGIFView(data: Self.gif(delays: [0.5])).beginScrub())
    #expect(!ScrubbableGIFView(data: Data("not a gif".utf8)).beginScrub())
  }

  /// A 4×2 GIF with one frame per delay.
  private static func gif(delays: [Double]) throws -> Data {
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, delays.count, nil))
    let context = try #require(CGContext(data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    for (index, delay) in delays.enumerated() {
      // ImageIO merges identical frames, so each one gets its own shade.
      context.setFillColor(gray: CGFloat(index) / CGFloat(delays.count), alpha: 1)
      context.fill(CGRect(x: 0, y: 0, width: 4, height: 2))
      let image = try #require(context.makeImage())
      let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary
      CGImageDestinationAddImage(destination, image, properties)
    }
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
  }
}
