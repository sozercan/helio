//
//  PostLayout.swift
//  Helio
//

import Defaults

/// How a subreddit's feed shows its posts, chosen per subreddit from the feed's options menu.
enum PostLayout: String, CaseIterable, Identifiable {
  /// Full rows with their media.
  case large
  /// Rows with a thumbnail.
  case compact
  /// A grid of large thumbnails (`CanvasGrid`).
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

  /// A subreddit's layout: canvas when it's one of `canvasSubreddits`, else compact or large as
  /// set for it, else as compact mode is set for every feed.
  static func of(_ subId: String, compactPerSubreddit: [String: Bool], compactByDefault: Bool, canvasSubreddits: Set<String>) -> PostLayout {
    if canvasSubreddits.contains(subId) {
      return .canvas
    }
    return (compactPerSubreddit[subId] ?? compactByDefault) ? .compact : .large
  }

  /// Sets this as `subId`'s layout in the settings it's kept in. Canvas keeps the subreddit's
  /// compact setting for when it's switched off.
  func apply(to subId: String, compactPerSubreddit: inout [String: Bool], canvasSubreddits: inout Set<String>) {
    switch self {
    case .canvas:
      canvasSubreddits.insert(subId)
    case .large, .compact:
      canvasSubreddits.remove(subId)
      compactPerSubreddit[subId] = self == .compact
    }
  }

  /// Sets this as `subId`'s layout.
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
