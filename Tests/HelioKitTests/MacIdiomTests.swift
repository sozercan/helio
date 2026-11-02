import Testing
@testable import HelioKit

struct MacIdiomTests {
  /// Off Mac, nothing is scaled: iPhone and iPad sizes stay as made.
  @Test func sizesAreUnscaledOutsideTheMacIdiom() {
    #expect(!MacIdiom.isActive)
    #expect(MacIdiom.scale == 1)
    #expect(MacIdiom.size(17) == 17)
    #expect(ContentTextScale.size(17, relativeTo: .title, dynamicTypeSize: .large) == 17)
  }
}
