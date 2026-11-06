//
//  ScreenStates.swift
//  Helio
//
//  A screen's state carried over when the posts tab rebuilds its screens in another layout.
//

import SwiftUI

/// The state screens keep across a change of layout. Folding or unfolding the iPhone Duo switches
/// the posts tab between its split view and its two panes (`SubredditsStack`), which builds every
/// screen anew: without this, a feed would reload and go back to its top, a post its comments, and
/// a web page would lose its history.
///
/// A screen asks for its model with `lease(_:owner:make:)` from its initializer, and calls
/// `adopt(in:)` with its `screenStateScope` on the lease it keeps once it shows. Outside a
/// handoff each lease makes its own model, so two screens of the same feed never share one. When
/// a layout changes (`beginHandoff(in:)`), the screens built for the new layout in the next moment
/// take over the models of the screens showing in it then, matched by name and owner: the
/// subreddit, post or other entity the screen shows, by identity, as its id changes once its
/// details load.
@MainActor
final class ScreenStates {
  static let shared = ScreenStates()

  /// How long the screens of a new layout have to take over the old ones' state. Some (those
  /// pushed on a stack) are only built once the old ones are gone.
  static let handoffDuration: TimeInterval = 2

  final class Entry {
    let name: String
    /// The layout the screen is in (`screenStateScope`).
    fileprivate weak var scope: AnyObject?
    /// Weak, so an entity made later at the same address never matches.
    private weak var owner: AnyObject?
    private let hasOwner: Bool
    let model: AnyObject
    /// The screens that adopted it.
    fileprivate var holders = 1
    /// The handoff a screen of the new layout took it over in, so a second screen doesn't.
    fileprivate var claimedIn: Int?

    fileprivate init(name: String, scope: AnyObject, owner: AnyObject?, model: AnyObject) {
      self.name = name
      self.scope = scope
      self.owner = owner
      self.hasOwner = owner != nil
      self.model = model
    }

    fileprivate func matches(name: String, owner: AnyObject?) -> Bool {
      guard name == self.name else { return false }
      guard hasOwner else { return owner == nil }
      return owner != nil && owner === self.owner
    }
  }

  /// The models of screens showing now.
  private var entries: [Entry] = []
  private var handoff = 0
  private var handoffEnds = Date.distantPast
  /// The models of the screens showing when the layout changed, kept until the handoff ends even
  /// if those screens go first.
  private var handedOff: [Entry] = []

  /// The layout of `scope` changed: the screens built in the next moment take over the state of
  /// those showing in it now; not of screens elsewhere, such as in other tabs, which stay. Tests
  /// end it themselves (`endsItself: false`), as the main actor can be busy with other tests for
  /// longer than a handoff.
  func beginHandoff(in scope: AnyObject, now: Date = .now, endsItself: Bool = true) {
    handoff += 1
    handoffEnds = now.addingTimeInterval(Self.handoffDuration)
    handedOff = entries.filter { $0.scope === scope }
    guard endsItself else { return }
    let current = handoff
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(Self.handoffDuration))
      self?.endHandoff(current)
    }
  }

  /// Drops the models no screen took over.
  func endHandoff(_ ending: Int? = nil) {
    guard ending == nil || ending == handoff else { return }
    handedOff = []
    entries.removeAll { $0.holders <= 0 }
  }

  /// The model for a screen named `name` showing `owner`: during a handoff, that of the screen it
  /// replaces, else a new one. Taken over only once the screen adopts the lease, as SwiftUI drops
  /// some views it initializes.
  func lease<Model: AnyObject>(_ name: String, owner: AnyObject?, now: Date = .now, make: @escaping () -> Model) -> ScreenStateLease<Model> {
    if now < handoffEnds, let entry = unclaimed(name: name, owner: owner, as: Model.self), let model = entry.model as? Model {
      return ScreenStateLease(model: model, make: make, name: name, owner: owner, store: self, entry: entry)
    }
    return ScreenStateLease(model: make(), make: make, name: name, owner: owner, store: self, entry: nil)
  }

  private func unclaimed<Model: AnyObject>(name: String, owner: AnyObject?, as _: Model.Type) -> Entry? {
    handedOff.first { $0.claimedIn != handoff && $0.matches(name: name, owner: owner) && $0.model is Model }
  }

  fileprivate func register(name: String, scope: AnyObject, owner: AnyObject?, model: AnyObject) -> Entry {
    let entry = Entry(name: name, scope: scope, owner: owner, model: model)
    entries.append(entry)
    return entry
  }

  /// Takes `entry` over for a screen that shows, or, if another screen of the new layout took it
  /// first (both were initialized before either showed), another old screen's of the same name and
  /// owner. Nil when none is left: the screen gets a model of its own.
  fileprivate func takeOver<Model: AnyObject>(_ entry: Entry, name: String, owner: AnyObject?, as _: Model.Type) -> Entry? {
    guard let chosen = entry.claimedIn != handoff ? entry : unclaimed(name: name, owner: owner, as: Model.self) else { return nil }
    chosen.claimedIn = handoff
    chosen.holders += 1
    if !entries.contains(where: { $0 === chosen }) {
      entries.append(chosen)
    }
    return chosen
  }

  fileprivate func release(_ entry: Entry) {
    entry.holders -= 1
    // Kept for the screens of the new layout until the handoff ends.
    if entry.holders <= 0, !handedOff.contains(where: { $0 === entry }) {
      entries.removeAll { $0 === entry }
    }
  }

  /// The models kept named `name`, for tests.
  func count(_ name: String) -> Int {
    entries.count { $0.name == name }
  }
}

/// A screen's hold on its model. The screen keeps it in a `@State`, which keeps only the lease
/// made by its first initialization; those its later initializations make are dropped unused,
/// which is why a lease only counts once adopted.
@MainActor
@Observable
final class ScreenStateLease<Model: AnyObject> {
  /// Observed: replaced when the screen shows, if another screen took this one's over first.
  private(set) var model: Model
  @ObservationIgnored private let make: () -> Model
  @ObservationIgnored private let name: String
  @ObservationIgnored private weak var owner: AnyObject?
  @ObservationIgnored private let store: ScreenStates?
  /// The model's entry: the old screen's until adopted, if handed over.
  @ObservationIgnored private var entry: ScreenStates.Entry?
  @ObservationIgnored private var adopted = false
  /// Taken over from a screen of the layout before; read once with `takeHandedOver()`.
  @ObservationIgnored private var handedOver: Bool
  /// The screen showed and `model` won't change again: a screen showing a view that can only be
  /// in one place (a web view) waits for it.
  private(set) var settled = false

  fileprivate init(model: Model, make: @escaping () -> Model, name: String, owner: AnyObject?, store: ScreenStates?, entry: ScreenStates.Entry?) {
    self.model = model
    self.make = make
    self.name = name
    self.owner = owner
    self.store = store
    self.entry = entry
    self.handedOver = entry != nil
  }

  /// A lease no other screen can take over, for a screen that isn't a place in the app's
  /// navigation, such as a context-menu preview.
  convenience init(unshared model: Model) {
    self.init(model: model, make: { model }, name: "", owner: nil, store: nil, entry: nil)
  }

  /// The screen shows with this lease, in the layout `scope`: a screen of that layout's next one
  /// can take its model over. Nothing without a scope, outside a layout that changes.
  func adopt(in scope: AnyObject?) {
    defer {
      if !settled {
        settled = true
      }
    }
    guard !adopted, let store else { return }
    if let candidate = entry {
      entry = nil
      if let taken = store.takeOver(candidate, name: name, owner: owner, as: Model.self), let takenModel = taken.model as? Model {
        adopted = true
        entry = taken
        if takenModel !== model {
          model = takenModel
        }
        return
      }
      // Another screen of the new layout took it first: this one starts afresh.
      handedOver = false
      model = make()
    }
    if let scope {
      adopted = true
      entry = store.register(name: name, scope: scope, owner: owner, model: model)
    }
  }

  /// Whether the model came from the screen this one replaced, once: the screen restores where
  /// the last one was scrolled to.
  func takeHandedOver() -> Bool {
    defer { handedOver = false }
    return handedOver
  }

  deinit {
    guard adopted, let entry, let store else { return }
    Task { @MainActor in store.release(entry) }
  }
}

extension EnvironmentValues {
  /// The layout whose screens hand their state over when it changes (`ScreenStates`): the posts
  /// tab's. Nil elsewhere, where screens keep theirs only as long as they show.
  @Entry var screenStateScope: AnyObject?
}
