import Testing
@testable import HelioKit

@MainActor
struct CommentsLoadTests {
  @Test func theNewestRequestWins() {
    let load = CommentsLoad()
    #expect(!load.started && !load.loaded)
    // The first load, then a refresh before it lands.
    let first = load.begin()
    let refresh = load.begin()
    #expect(load.started)
    #expect(!load.isCurrent(first))
    #expect(load.isCurrent(refresh))
    // Only the refresh ends the loading state.
    #expect(!load.loaded)
    load.finish()
    #expect(load.loaded)
  }

  @Test func failedLoadReportsFailureAndResetsSpinnerOnRetry() {
    let load = CommentsLoad()
    _ = load.begin()
    load.finish(failed: true)
    #expect(load.loaded)
    #expect(load.failed)

    _ = load.begin()
    #expect(!load.loaded)
    #expect(!load.failed)

    load.finish(failed: false)
    #expect(load.loaded)
    #expect(!load.failed)
  }
}
