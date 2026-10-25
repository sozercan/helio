import Testing
@testable import winston

struct SearchHistoryTests {
  private func queries(_ items: [SearchHistoryItem]) -> [String] { items.map(\.query) }

  @Test func recordsNewestFirstAndMovesRepeatsToTop() {
    var items: [SearchHistoryItem] = []
    items = SearchHistory.record("swift", type: .subreddit, in: items)
    items = SearchHistory.record("apple", type: .subreddit, in: items)
    items = SearchHistory.record("  Swift ", type: .subreddit, in: items)
    #expect(queries(items) == ["Swift", "apple"])
  }

  @Test func keepsSameQueryForDifferentTypesSeparate() {
    var items = SearchHistory.record("apple", type: .subreddit, in: [])
    items = SearchHistory.record("apple", type: .post, in: items)
    #expect(items.map(\.type) == [.post, .subreddit])
  }

  @Test func ignoresBlankQueries() {
    #expect(SearchHistory.record("   ", type: .user, in: []).isEmpty)
  }

  @Test func prunesOldRecentsButKeepsFavorites() {
    var items = SearchHistory.record("pinned", type: .subreddit, in: [])
    items[0].isFavorite = true
    for i in 0..<(SearchHistory.maxRecents + 5) {
      items = SearchHistory.record("q\(i)", type: .post, in: items)
    }
    #expect(items.filter { !$0.isFavorite }.count == SearchHistory.maxRecents)
    #expect(items.contains { $0.query == "pinned" && $0.isFavorite })
    #expect(!items.contains { $0.query == "q0" })
  }

  @Test func repeatingAFavoriteKeepsItFavorite() {
    var items = SearchHistory.record("pinned", type: .subreddit, in: [])
    items[0].isFavorite = true
    items = SearchHistory.record("pinned", type: .subreddit, in: items)
    #expect(items.count == 1)
    #expect(items[0].isFavorite)
  }

  @Test func suggestsMatchesWithFavoritesFirst() {
    var items: [SearchHistoryItem] = []
    for query in ["swiftui", "taylor swift", "swift", "rust"] {
      items = SearchHistory.record(query, type: .subreddit, in: items)
    }
    items[items.firstIndex { $0.query == "swiftui" }!].isFavorite = true
    #expect(queries(SearchHistory.suggestions(for: "SWIFT", in: items)) == ["swiftui", "taylor swift"])
    #expect(SearchHistory.suggestions(for: " ", in: items).isEmpty)
  }
}
