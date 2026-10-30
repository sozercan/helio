//
//  isVideoPlayer.swift
//  Helio
//
//  Created by Igor Marcossi on 31/07/23.
//

import AVKit
import Foundation

extension AVPlayer {
  var isPlaying: Bool {
    self.timeControlStatus == AVPlayer.TimeControlStatus.playing
  }
}
