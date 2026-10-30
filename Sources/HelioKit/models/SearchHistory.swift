//
//  SearchHistory.swift
//  Helio
//
//  Recent and favorite searches, kept on device.
//

import Defaults
import Foundation

struct SearchHistoryItem: Codable, Hashable, Identifiable, Defaults.Serializable {
  var id = UUID()
  var query: String
  var type: SearchType
  var date = Date()
  var isFavorite = false
}

extension Defaults.Keys {
  static let searchHistory = Key<[SearchHistoryItem]>("searchHistory", default: [])
}

enum SearchHistory {
  /// Non-favorite searches kept; favorites are never pruned.
  static let maxRecents = 20

  /// Adds or refreshes a search, moving it to the top.
  static func record(_ query: String, type: SearchType, in items: [SearchHistoryItem]) -> [SearchHistoryItem] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return items }
    var items = items
    var item = SearchHistoryItem(query: query, type: type)
    if let i = items.firstIndex(where: { $0.type == type && $0.query.caseInsensitiveCompare(query) == .orderedSame }) {
      item.isFavorite = items[i].isFavorite
      items.remove(at: i)
    }
    items.insert(item, at: 0)
    var recents = 0
    return items.filter { $0.isFavorite || { recents += 1
      return recents <= maxRecents
    }() }
  }

  /// Past searches containing `text`, favorites first.
  static func suggestions(for text: String, in items: [SearchHistoryItem], limit: Int = 5) -> [SearchHistoryItem] {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return [] }
    let matches = items.filter { $0.query.localizedCaseInsensitiveContains(text) && $0.query.caseInsensitiveCompare(text) != .orderedSame }
    return Array((matches.filter(\.isFavorite) + matches.filter { !$0.isFavorite }).prefix(limit))
  }
}
