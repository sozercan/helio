import Foundation
import Testing
@testable import HelioKit

/// Theme parts and swipe actions keep their large fields in boxes (`Boxed`), so the views that
/// hold them stay small. They still have to behave, and encode, as the plain values.
struct BoxedTests {
  private struct Plain: Codable, Equatable {
    var name: String
    var tags: [String]
  }

  private struct Wrapped: Codable, Hashable {
    @Boxed var name: String
    @Boxed var tags: [String]
  }

  @Test func aBoxedFieldEncodesAsItsValue() throws {
    let wrapped = Wrapped(name: "a", tags: ["b"])
    #expect(try JSONDecoder().decode(Plain.self, from: JSONEncoder().encode(wrapped)) == Plain(name: "a", tags: ["b"]))
    let decoded = try JSONDecoder().decode(Wrapped.self, from: JSONEncoder().encode(Plain(name: "c", tags: [])))
    #expect(decoded.name == "c")
    #expect(decoded.tags.isEmpty)
  }

  @Test func changingACopyLeavesTheOriginal() {
    let original = Wrapped(name: "a", tags: [])
    var copy = original
    copy.name = "b"
    #expect(original.name == "a")
    #expect(copy != original)
    copy.name = "a"
    #expect(copy == original)
    #expect(copy.hashValue == original.hashValue)
  }

  @Test func themePartsStaySmall() {
    #expect(MemoryLayout<BadgeTheme>.size < 128)
    #expect(MemoryLayout<CommentsSectionTheme>.size < 64)
    #expect(MemoryLayout<SubPostsListTheme>.size < 128)
    #expect(MemoryLayout<SwipeActionsSet>.size < 64)
  }

  @Test func aNestedChangeLeavesTheTheme() {
    var comments = defaultTheme.comments
    comments.theme.badge.authorText.size += 1
    #expect(comments.theme.badge.authorText.size == defaultTheme.comments.theme.badge.authorText.size + 1)
    #expect(comments != defaultTheme.comments)
  }

  @Test func swipeActionsDecodeAsTheyWereSaved() throws {
    let decoded = try JSONDecoder().decode(SwipeActionsSet.self, from: JSONEncoder().encode(DEFAULT_POST_SWIPE_ACTIONS))
    #expect(decoded == DEFAULT_POST_SWIPE_ACTIONS)
    #expect(decoded.leftFirst.id == DEFAULT_POST_SWIPE_ACTIONS.leftFirst.id)
  }
}
