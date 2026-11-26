import Testing
@testable import HelioKit

@MainActor
struct CommentsLoadTests {
  @Test func theNewestRequestWins() {
    let load = CommentsLoad()
    #expect(!load.started && !load.loaded)
    let first = load.begin()
    let refresh = load.begin()
    #expect(load.started)
    #expect(!load.isCurrent(first))
    #expect(load.isCurrent(refresh))
    #expect(!load.loaded)
    load.finish()
    #expect(load.loaded)
  }
}
