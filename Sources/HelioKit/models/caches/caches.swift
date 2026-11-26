import Foundation
import NukeUI
import UIKit
import YouTubePlayerKit

class Caches {
  static let postsAttrStr = BaseCache<AttributedString>(cacheLimit: 100)
  static let videos = BaseCache<SharedVideo>(cacheLimit: 12)
  static let streamable = BaseCache<StreamableCached>(cacheLimit: 100)
}
