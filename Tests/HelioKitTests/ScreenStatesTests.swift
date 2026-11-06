import Foundation
import Testing
@testable import HelioKit

@MainActor
struct ScreenStatesTests {
  private final class Model {}

  private let start = Date(timeIntervalSinceReferenceDate: 0)

  @Test func screensOfTheSameFeedKeepTheirOwnStateOutsideALayoutChange() {
    let states = ScreenStates()
    let first = states.lease("feed:home", now: start) { Model() }
    first.adopt()
    let second = states.lease("feed:home", now: start) { Model() }
    #expect(first.model !== second.model)
    #expect(!second.takeHandedOver())
  }

  @Test func theScreenBuiltForTheNewLayoutTakesOverTheOneItReplaces() {
    let states = ScreenStates()
    let old = states.lease("feed:home", now: start) { Model() }
    old.adopt()
    states.beginHandoff(now: start)
    let new = states.lease("feed:home", now: start) { Model() }
    #expect(new.model === old.model)
    #expect(new.takeHandedOver())
    // Once: the screen restores its scroll position on its first appearance only.
    #expect(!new.takeHandedOver())
  }

  @Test func oneOldScreenHandsItsStateToOneNewScreen() {
    let states = ScreenStates()
    let old = states.lease("feed:home", now: start) { Model() }
    old.adopt()
    states.beginHandoff(now: start)
    let new = states.lease("feed:home", now: start) { Model() }
    // A later initialization of the new screen, which its state drops, or a second screen.
    let another = states.lease("feed:home", now: start) { Model() }
    #expect(new.model === old.model)
    #expect(another.model !== old.model)
  }

  @Test func aLeaseNoScreenKeptIsNotHandedOver() {
    let states = ScreenStates()
    let unused = states.lease("feed:home", now: start) { Model() }
    states.beginHandoff(now: start)
    let new = states.lease("feed:home", now: start) { Model() }
    #expect(new.model !== unused.model)
  }

  @Test func otherFeedsDoNotTakeEachOthersState() {
    let states = ScreenStates()
    let home = states.lease("feed:home", now: start) { Model() }
    home.adopt()
    states.beginHandoff(now: start)
    let popular = states.lease("feed:popular", now: start) { Model() }
    #expect(popular.model !== home.model)
  }

  @Test func theHandoffEndsShortlyAfterTheLayoutChanges() {
    let states = ScreenStates()
    let old = states.lease("feed:home", now: start) { Model() }
    old.adopt()
    states.beginHandoff(now: start)
    let later = start.addingTimeInterval(ScreenStates.handoffDuration + 1)
    let new = states.lease("feed:home", now: later) { Model() }
    #expect(new.model !== old.model)
  }

  @Test func aScreenPushedAfterTheOldOneWentAwayStillTakesItsStateOver() async {
    let states = ScreenStates()
    var old: ScreenStateLease<Model>? = states.lease("feed:home", now: start) { Model() }
    old?.adopt()
    let model = old?.model
    states.beginHandoff(now: start)
    old = nil
    // The lease lets go on the main actor after it's released.
    for _ in 0 ..< 5 {
      await Task.yield()
    }
    let new = states.lease("feed:home", now: start.addingTimeInterval(1)) { Model() }
    #expect(new.model === model)
  }

  @Test func aModelGoesOnceItsLastScreenHasBeenGoneAWhile() async {
    let states = ScreenStates()
    var old: ScreenStateLease<Model>? = states.lease("feed:home") { Model() }
    old?.adopt()
    old = nil
    for _ in 0 ..< 5 {
      await Task.yield()
    }
    #expect(states.count("feed:home") == 1)
    _ = states.lease("feed:other", now: Date.now.addingTimeInterval(ScreenStates.handoffDuration + 1)) { Model() }
    #expect(states.count("feed:home") == 0)
  }

  @Test func aPreviewNeverHandsItsStateOver() {
    let states = ScreenStates()
    let preview = ScreenStateLease(unshared: Model())
    preview.adopt()
    states.beginHandoff(now: start)
    let new = states.lease("post:abc|", now: start) { Model() }
    #expect(new.model !== preview.model)
  }
}
