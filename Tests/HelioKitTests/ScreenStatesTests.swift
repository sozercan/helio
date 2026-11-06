import Foundation
import Testing
@testable import HelioKit

@MainActor
struct ScreenStatesTests {
  private final class Model {}
  private final class Owner {}

  private let start = Date(timeIntervalSinceReferenceDate: 0)
  private let home = Owner()
  /// The posts tab's layout.
  private let posts = Owner()

  /// The lease lets go on the main actor after it's released.
  private func letLeasesGo() async {
    for _ in 0 ..< 5 {
      await Task.yield()
    }
  }

  @Test func screensOfTheSameFeedKeepTheirOwnStateOutsideALayoutChange() {
    let states = ScreenStates()
    let first = states.lease("feed", owner: home, now: start) { Model() }
    first.adopt(in: posts)
    let second = states.lease("feed", owner: home, now: start) { Model() }
    #expect(first.model !== second.model)
    #expect(!second.takeHandedOver())
  }

  @Test func theScreenBuiltForTheNewLayoutTakesOverTheOneItReplaces() {
    let states = ScreenStates()
    let old = states.lease("feed", owner: home, now: start) { Model() }
    old.adopt(in: posts)
    states.beginHandoff(in: posts, now: start, endsItself: false)
    let new = states.lease("feed", owner: home, now: start) { Model() }
    new.adopt(in: posts)
    #expect(new.model === old.model)
    #expect(new.takeHandedOver())
    // Once: the screen restores its scroll position on its first appearance only.
    #expect(!new.takeHandedOver())
  }

  @Test func oneOldScreenHandsItsStateToOneNewScreen() {
    let states = ScreenStates()
    let old = states.lease("feed", owner: home, now: start) { Model() }
    old.adopt(in: posts)
    states.beginHandoff(in: posts, now: start, endsItself: false)
    let new = states.lease("feed", owner: home, now: start) { Model() }
    new.adopt(in: posts)
    let another = states.lease("feed", owner: home, now: start) { Model() }
    #expect(new.model === old.model)
    #expect(another.model !== old.model)
  }

  @Test func twoNewScreensInitializedTogetherDoNotShareOneOldScreensState() {
    let states = ScreenStates()
    let old = states.lease("feed", owner: home, now: start) { Model() }
    old.adopt(in: posts)
    states.beginHandoff(in: posts, now: start, endsItself: false)
    let first = states.lease("feed", owner: home, now: start) { Model() }
    let second = states.lease("feed", owner: home, now: start) { Model() }
    // Both start out with the old screen's, until they show.
    #expect(second.model === old.model && !second.settled)
    first.adopt(in: posts)
    second.adopt(in: posts)
    #expect(first.model === old.model)
    #expect(second.model !== old.model)
    #expect(first.takeHandedOver())
    #expect(!second.takeHandedOver())
    #expect(first.settled && second.settled)
  }

  @Test func twoNewScreensTakeOverTwoOldScreensOfTheSameFeed() {
    let states = ScreenStates()
    let oldA = states.lease("feed", owner: home, now: start) { Model() }
    oldA.adopt(in: posts)
    let oldB = states.lease("feed", owner: home, now: start) { Model() }
    oldB.adopt(in: posts)
    states.beginHandoff(in: posts, now: start, endsItself: false)
    let first = states.lease("feed", owner: home, now: start) { Model() }
    let second = states.lease("feed", owner: home, now: start) { Model() }
    first.adopt(in: posts)
    second.adopt(in: posts)
    #expect(first.model === oldA.model)
    #expect(second.model === oldB.model)
  }

  @Test func anInitializationSwiftUIDropsDoesNotUseUpTheHandoff() {
    let states = ScreenStates()
    let old = states.lease("feed", owner: home, now: start) { Model() }
    old.adopt(in: posts)
    states.beginHandoff(in: posts, now: start, endsItself: false)
    // Made and dropped without showing.
    _ = states.lease("feed", owner: home, now: start) { Model() }
    let new = states.lease("feed", owner: home, now: start) { Model() }
    #expect(new.model === old.model)
  }

  @Test func aLeaseNoScreenKeptIsNotHandedOver() {
    let states = ScreenStates()
    let unused = states.lease("feed", owner: home, now: start) { Model() }
    states.beginHandoff(in: posts, now: start, endsItself: false)
    let new = states.lease("feed", owner: home, now: start) { Model() }
    #expect(new.model !== unused.model)
  }

  @Test func otherFeedsDoNotTakeEachOthersState() {
    let states = ScreenStates()
    let first = states.lease("feed", owner: home, now: start) { Model() }
    first.adopt(in: posts)
    states.beginHandoff(in: posts, now: start, endsItself: false)
    let popular = states.lease("feed", owner: Owner(), now: start) { Model() }
    #expect(popular.model !== first.model)
  }

  @Test func screensWithoutAnOwnerMatchByName() {
    let states = ScreenStates()
    let old = states.lease("web:https://example.com", owner: nil, now: start) { Model() }
    old.adopt(in: posts)
    states.beginHandoff(in: posts, now: start, endsItself: false)
    let other = states.lease("web:https://example.org", owner: nil, now: start) { Model() }
    let new = states.lease("web:https://example.com", owner: nil, now: start) { Model() }
    #expect(other.model !== old.model)
    #expect(new.model === old.model)
  }

  @Test func theHandoffEndsShortlyAfterTheLayoutChanges() {
    let states = ScreenStates()
    let old = states.lease("feed", owner: home, now: start) { Model() }
    old.adopt(in: posts)
    states.beginHandoff(in: posts, now: start, endsItself: false)
    let later = start.addingTimeInterval(ScreenStates.handoffDuration + 1)
    let new = states.lease("feed", owner: home, now: later) { Model() }
    #expect(new.model !== old.model)
  }

  @Test func aScreenPushedAfterTheOldOneWentAwayStillTakesItsStateOver() async {
    let states = ScreenStates()
    var old: ScreenStateLease<Model>? = states.lease("feed", owner: home, now: start) { Model() }
    old?.adopt(in: posts)
    let model = old?.model
    states.beginHandoff(in: posts, now: start, endsItself: false)
    old = nil
    await letLeasesGo()
    let new = states.lease("feed", owner: home, now: start.addingTimeInterval(1)) { Model() }
    #expect(new.model === model)
  }

  @Test func aScreenClosedBeforeTheLayoutChangesHandsNothingOver() async {
    let states = ScreenStates()
    var closed: ScreenStateLease<Model>? = states.lease("feed", owner: home, now: start) { Model() }
    closed?.adopt(in: posts)
    let closedModel = closed?.model
    closed = nil
    await letLeasesGo()
    // Opened again, then the layout changes: the new screen gets the open one's, not the closed one's.
    let reopened = states.lease("feed", owner: home, now: start) { Model() }
    reopened.adopt(in: posts)
    states.beginHandoff(in: posts, now: start, endsItself: false)
    let new = states.lease("feed", owner: home, now: start) { Model() }
    #expect(new.model === reopened.model)
    #expect(new.model !== closedModel)
  }

  @Test func aSecondLayoutChangeHandsOverOnlyWhatShowsThen() async {
    let states = ScreenStates()
    var gone: ScreenStateLease<Model>? = states.lease("web:https://example.com", owner: nil, now: start) { Model() }
    gone?.adopt(in: posts)
    let goneModel = gone?.model
    states.beginHandoff(in: posts, now: start, endsItself: false)
    // Closed during the first change, before any screen took it over.
    gone = nil
    await letLeasesGo()
    // Folded back before that handoff ended: a page opened at that address since gets a new one.
    states.beginHandoff(in: posts, now: start, endsItself: false)
    let new = states.lease("web:https://example.com", owner: nil, now: start) { Model() }
    new.adopt(in: posts)
    #expect(new.model !== goneModel)
  }

  @Test func aScreenBuiltBeforeAnotherLayoutChangeDoesNotGetWhatThatOneDropped() async {
    let states = ScreenStates()
    var old: ScreenStateLease<Model>? = states.lease("feed", owner: home, now: start) { Model() }
    old?.adopt(in: posts)
    let oldModel = old?.model
    states.beginHandoff(in: posts, now: start, endsItself: false)
    let new = states.lease("feed", owner: home, now: start) { Model() }
    old = nil
    await letLeasesGo()
    // The layout changes again before the new screen shows.
    states.beginHandoff(in: posts, now: start, endsItself: false)
    new.adopt(in: posts)
    #expect(new.model !== oldModel)
    #expect(!new.takeHandedOver())
  }

  @Test func aCoveredScreenTakesItsStateOverWhenItShowsAfterTheHandoff() async {
    let states = ScreenStates()
    var old: ScreenStateLease<Model>? = states.lease("post|", owner: home, now: start) { Model() }
    old?.adopt(in: posts)
    let oldModel = old?.model
    states.beginHandoff(in: posts, now: start, endsItself: false)
    // Built under a web page, so it shows only once Back uncovers it.
    let covered = states.lease("post|", owner: home, now: start) { Model() }
    old = nil
    await letLeasesGo()
    states.endHandoff()
    covered.adopt(in: posts)
    #expect(covered.model === oldModel)
    #expect(covered.takeHandedOver())
  }

  @Test func aClosedScreensModelGoesRightAway() async {
    let states = ScreenStates()
    var old: ScreenStateLease<Model>? = states.lease("feed", owner: home) { Model() }
    old?.adopt(in: posts)
    #expect(states.count("feed") == 1)
    old = nil
    await letLeasesGo()
    #expect(states.count("feed") == 0)
  }

  @Test func aModelNoScreenTookOverGoesWhenTheHandoffEnds() async {
    let states = ScreenStates()
    var old: ScreenStateLease<Model>? = states.lease("feed", owner: home, now: start) { Model() }
    old?.adopt(in: posts)
    states.beginHandoff(in: posts, now: start, endsItself: false)
    old = nil
    await letLeasesGo()
    #expect(states.count("feed") == 1)
    states.endHandoff()
    #expect(states.count("feed") == 0)
  }

  @Test func screensOutsideTheLayoutThatChangedKeepTheirState() {
    let states = ScreenStates()
    // The same subreddit open in another tab.
    let elsewhere = states.lease("feed", owner: home, now: start) { Model() }
    elsewhere.adopt(in: Owner())
    let old = states.lease("feed", owner: home, now: start) { Model() }
    old.adopt(in: posts)
    states.beginHandoff(in: posts, now: start, endsItself: false)
    let new = states.lease("feed", owner: home, now: start) { Model() }
    #expect(new.model === old.model)
  }

  @Test func aScreenOutsideALayoutThatChangesKeepsNothing() {
    let states = ScreenStates()
    let screen = states.lease("feed", owner: home, now: start) { Model() }
    screen.adopt(in: nil)
    #expect(states.count("feed") == 0)
    #expect(screen.settled)
  }

  @Test func aPreviewNeverHandsItsStateOver() {
    let states = ScreenStates()
    let preview = ScreenStateLease(unshared: Model())
    preview.adopt(in: posts)
    states.beginHandoff(in: posts, now: start, endsItself: false)
    let new = states.lease("post|", owner: home, now: start) { Model() }
    #expect(new.model !== preview.model)
  }
}
