import Foundation
import SwiftUI

class CommentUtils {
  static let shared = CommentUtils()

  private init() {}

  struct AnchorsKey: PreferenceKey {
    typealias Value = [String: Anchor<CGPoint>]
    static var defaultValue: Value {
      [:]
    }

    static func reduce(value: inout Value, nextValue: () -> Value) {
      value.merge(nextValue()) { $1 }
    }
  }

  func topCommentRow(of anchors: CommentUtils.AnchorsKey.Value, in proxy: GeometryProxy) -> String? {
    var yBest = CGFloat.infinity
    var answer: String?
    for (row, anchor) in anchors {
      let y = proxy[anchor].y
      guard y >= 0, y < yBest else { continue }
      answer = row
      yBest = y
    }
    return answer
  }
}
