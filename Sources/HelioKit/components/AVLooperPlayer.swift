import AVKit
import Foundation

class AVLooperPlayer: AVQueuePlayer {
  private var looper: AVPlayerLooper!

  override convenience init(url: URL) {
    let playerItem = AVPlayerItem(url: url)
    self.init(playerItem: playerItem)
    looper = AVPlayerLooper(player: self, templateItem: playerItem)
  }
}
