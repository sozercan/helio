//
//  ScreenStates.swift
//  Helio
//
//  A screen's state carried over when the posts tab rebuilds its screens in another layout.
//

import Foundation

/// The state screens keep across a change of layout. Folding or unfolding the iPhone Duo switches
/// the posts tab between its split view and its two panes (`SubredditsStack`), which builds every
/// screen anew: without this, a feed would reload and go back to its top, a post its comments, and
/// a web page would lose its history.
///
/// A screen asks for its model with `lease(_:make:)` from its initializer and calls `adopt()` on
/// the lease it keeps once it shows. Outside a handoff each lease makes its own model, so two
/// screens of the same feed never share one. For a moment after the layout changes
/// (`beginHandoff()`), the screens built for the new layout take over the models of the ones they
/// replace, matched by key.
@MainActor
final class ScreenStates {
  static let shared = ScreenStates()

  /// How long the screens of a new layout have to take over the old ones' state, and how long a
  /// model outlives its last screen: some screens of the new layout (those pushed on a stack) are
  /// only built once the old ones are gone.
  static let handoffDuration: TimeInterval = 2

  final class Entry {
    let key: String
    let model: AnyObject
    /// The leases kept by screens.
    fileprivate var holders = 1
    /// When the last screen holding it went away.
    fileprivate var releasedAt: Date?
    /// The handoff a screen of the new layout took it over in, so a second screen doesn't.
    fileprivate var claimedIn: Int?

    fileprivate init(key: String, model: AnyObject) {
      self.key = key
      self.model = model
    }
  }

  private var entries: [Entry] = []
  private var handoff = 0
  private var handoffEnds = Date.distantPast

  /// The layout changed: the screens built in the next moment take over the state of those they
  /// replace.
  func beginHandoff(now: Date = .now) {
    handoff += 1
    handoffEnds = now.addingTimeInterval(Self.handoffDuration)
  }

  /// The model for a screen keyed `key`: during a handoff, that of the screen it replaces, else a
  /// new one.
  func lease<Model: AnyObject>(_ key: String, now: Date = .now, make: () -> Model) -> ScreenStateLease<Model> {
    prune(now: now)
    if now < handoffEnds, let entry = entries.first(where: { $0.key == key && $0.claimedIn != handoff && $0.model is Model }), let model = entry.model as? Model {
      entry.claimedIn = handoff
      entry.holders += 1
      entry.releasedAt = nil
      return ScreenStateLease(model: model, key: key, store: self, entry: entry)
    }
    return ScreenStateLease(model: make(), key: key, store: self, entry: nil)
  }

  fileprivate func register(key: String, model: AnyObject) -> Entry {
    let entry = Entry(key: key, model: model)
    entries.append(entry)
    return entry
  }

  fileprivate func release(_ entry: Entry, now: Date = .now) {
    entry.holders -= 1
    if entry.holders <= 0 {
      entry.releasedAt = now
    }
  }

  private func prune(now: Date) {
    entries.removeAll { entry in
      guard entry.holders <= 0, let releasedAt = entry.releasedAt else { return false }
      return now.timeIntervalSince(releasedAt) > Self.handoffDuration
    }
  }

  /// The models kept for `key`, for tests.
  func count(_ key: String) -> Int {
    entries.count { $0.key == key }
  }
}

/// A screen's hold on its model. The screen keeps it in a `@State`, which keeps only the lease
/// made by its first initialization; those its later initializations make are dropped unused,
/// which is why a lease only counts once adopted.
@MainActor
final class ScreenStateLease<Model: AnyObject> {
  let model: Model
  private let key: String
  private let store: ScreenStates?
  private var entry: ScreenStates.Entry?
  /// Taken over from a screen of the layout before; read once with `takeHandedOver()`.
  private var handedOver: Bool

  fileprivate init(model: Model, key: String, store: ScreenStates?, entry: ScreenStates.Entry?) {
    self.model = model
    self.key = key
    self.store = store
    self.entry = entry
    self.handedOver = entry != nil
  }

  /// A lease no other screen can take over, for a screen that isn't a place in the app's
  /// navigation, such as a context-menu preview.
  convenience init(unshared model: Model) {
    self.init(model: model, key: "", store: nil, entry: nil)
  }

  /// The screen shows with this lease: a screen of the next layout can take its model over.
  func adopt() {
    guard entry == nil, let store else { return }
    entry = store.register(key: key, model: model)
  }

  /// Whether the model came from the screen this one replaced, once: the screen restores where
  /// the last one was scrolled to.
  func takeHandedOver() -> Bool {
    defer { handedOver = false }
    return handedOver
  }

  deinit {
    guard let entry, let store else { return }
    Task { @MainActor in store.release(entry) }
  }
}
