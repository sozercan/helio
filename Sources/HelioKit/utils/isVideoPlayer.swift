import AVKit
import Foundation

extension AVPlayer {
  var isPlaying: Bool {
    self.timeControlStatus == AVPlayer.TimeControlStatus.playing
  }
}
