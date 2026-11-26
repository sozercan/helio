import Defaults

enum PostLayout: String, CaseIterable, Identifiable {
  case large
  case compact
  case canvas

  var id: String {
    rawValue
  }

  var title: String {
    switch self {
    case .large: "Large Posts"
    case .compact: "Compact Posts"
    case .canvas: "Canvas"
    }
  }

  var systemImage: String {
    switch self {
    case .large: "rectangle.expand.vertical"
    case .compact: "rectangle.compress.vertical"
    case .canvas: "square.grid.2x2"
    }
  }

  static func available(for subId: String) -> [PostLayout] {
    subId == savedKeyword ? [.large, .compact] : allCases
  }

  static func isCanvas(_ subId: String, canvasSubreddits: Set<String>) -> Bool {
    canvasSubreddits.contains(subId) && available(for: subId).contains(.canvas)
  }

  static func of(_ subId: String, compactPerSubreddit: [String: Bool], compactByDefault: Bool, canvasSubreddits: Set<String>) -> PostLayout {
    if isCanvas(subId, canvasSubreddits: canvasSubreddits) {
      return .canvas
    }
    return (compactPerSubreddit[subId] ?? compactByDefault) ? .compact : .large
  }

  func apply(to subId: String, compactPerSubreddit: inout [String: Bool], canvasSubreddits: inout Set<String>) {
    switch self {
    case .canvas:
      canvasSubreddits.insert(subId)
    case .large, .compact:
      canvasSubreddits.remove(subId)
      compactPerSubreddit[subId] = self == .compact
    }
  }

  func save(for subId: String) {
    var compact = Defaults[.SubredditFeedDefSettings].compactPerSubreddit
    var canvas = Defaults[.canvasSubreddits]
    apply(to: subId, compactPerSubreddit: &compact, canvasSubreddits: &canvas)
    if compact != Defaults[.SubredditFeedDefSettings].compactPerSubreddit {
      Defaults[.SubredditFeedDefSettings].compactPerSubreddit = compact
    }
    if canvas != Defaults[.canvasSubreddits] {
      Defaults[.canvasSubreddits] = canvas
    }
  }
}
