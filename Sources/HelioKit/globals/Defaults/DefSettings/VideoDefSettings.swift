import Defaults

struct VideoDefSettings: Equatable, Hashable, Codable, Defaults.Serializable {
  var autoPlay: Bool = true
  var mute: Bool = false
  var pauseBGAudioOnFullscreen: Bool = true
  var loop: Bool = true
}
