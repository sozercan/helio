import Foundation
import Testing
@testable import HelioKit

@MainActor
struct ScreenStatesTests {
  private final class Model {}
  private final class Owner {}

  private let start = Date(timeIntervalSinceReferenceDate: 0)
  private let home = Owner()
  private let posts = Owner()

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
    await states.waitForNextRelease { old = nil }
    let new = states.lease("feed", owner: home, now: start.addingTimeInterval(1)) { Model() }
    #expect(new.model === model)
  }

  @Test func aScreenClosedBeforeTheLayoutChangesHandsNothingOver() async {
    let states = ScreenStates()
    var closed: ScreenStateLease<Model>? = states.lease("feed", owner: home, now: start) { Model() }
    closed?.adopt(in: posts)
    let closedModel = closed?.model
    await states.waitForNextRelease { closed = nil }
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
    await states.waitForNextRelease { gone = nil }
    states.beginHandoff(in: posts, now: start, endsItself: false)
    let new = states.lease("web:https://example.com", owner: nil, now: start) { Model() }
    new.adopt(in: posts)
    #expect(new.model !== goneModel)
  }

  @Test func aCoveredScreenKeepsItsStateAcrossAnotherLayoutChange() async {
    let states = ScreenStates()
    var old: ScreenStateLease<Model>? = states.lease("post|", owner: home, now: start) { Model() }
    old?.adopt(in: posts)
    let oldModel = old?.model
    states.beginHandoff(in: posts, now: start, endsItself: false)
    var covered: ScreenStateLease<Model>? = states.lease("post|", owner: home, now: start) { Model() }
    await states.waitForNextRelease { old = nil }
    states.endHandoff()
    states.beginHandoff(in: posts, now: start, endsItself: false)
    let next = states.lease("post|", owner: home, now: start) { Model() }
    await states.waitForNextRelease { covered = nil }
    states.endHandoff()
    next.adopt(in: posts)
    #expect(covered == nil)
    #expect(next.model === oldModel)
    #expect(next.takeHandedOver())
  }

  @Test func aCoveredScreenTakesItsStateOverWhenItShowsAfterTheHandoff() async {
    let states = ScreenStates()
    var old: ScreenStateLease<Model>? = states.lease("post|", owner: home, now: start) { Model() }
    old?.adopt(in: posts)
    let oldModel = old?.model
    states.beginHandoff(in: posts, now: start, endsItself: false)
    let covered = states.lease("post|", owner: home, now: start) { Model() }
    await states.waitForNextRelease { old = nil }
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
    await states.waitForNextRelease { old = nil }
    #expect(states.count("feed") == 0)
  }

  @Test func aModelNoScreenTookOverGoesWhenTheHandoffEnds() async {
    let states = ScreenStates()
    var old: ScreenStateLease<Model>? = states.lease("feed", owner: home, now: start) { Model() }
    old?.adopt(in: posts)
    states.beginHandoff(in: posts, now: start, endsItself: false)
    await states.waitForNextRelease { old = nil }
    #expect(states.count("feed") == 1)
    states.endHandoff()
    #expect(states.count("feed") == 0)
  }

  @Test func screensOutsideTheLayoutThatChangedKeepTheirState() {
    let states = ScreenStates()
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

  @Test func userViewSessionHandsSelectedSectionOverAcrossLayoutChanges() {
    let states = ScreenStates()
    let user = User(id: "someone")
    let old = states.lease("user", owner: user, now: start) { UserViewSession() }
    old.adopt(in: posts)
    old.model.selectedSection = .submitted

    states.beginHandoff(in: posts, now: start, endsItself: false)
    let new = states.lease("user", owner: user, now: start) { UserViewSession() }
    new.adopt(in: posts)
    #expect(new.model === old.model)
    #expect(new.model.selectedSection == .submitted)
  }
}
