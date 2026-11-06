import Foundation
import Testing
@testable import HelioKit

/// A theme keeps its parts in a box its copies share, so views that read it stay small. It still
/// has to behave as a value.
struct HelioThemeTests {
  @Test func aViewHoldsAThemeAsAPointer() {
    #expect(MemoryLayout<HelioTheme>.size == MemoryLayout<Int>.size)
  }

  @Test func changingACopyLeavesTheOriginal() {
    var copy = defaultTheme
    copy.posts.inlineFloatingPill.toggle()
    copy.metadata.name = "Copy"
    #expect(copy.posts.inlineFloatingPill != defaultTheme.posts.inlineFloatingPill)
    #expect(defaultTheme.metadata.name != "Copy")
    #expect(copy != defaultTheme)
  }

  @Test func themesWithTheSamePartsAreEqual() {
    let rebuilt = HelioTheme(metadata: defaultTheme.metadata, id: defaultTheme.id, postLinks: defaultTheme.postLinks, posts: defaultTheme.posts, comments: defaultTheme.comments, lists: defaultTheme.lists, general: defaultTheme.general)
    #expect(rebuilt == defaultTheme)
    #expect(rebuilt.hashValue == defaultTheme.hashValue)
    var changedBack = defaultTheme
    changedBack.posts.commentsDistance += 1
    changedBack.posts.commentsDistance -= 1
    #expect(changedBack == defaultTheme)
  }
}
