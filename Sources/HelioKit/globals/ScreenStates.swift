import SwiftUI

@MainActor
final class ScreenStates {
  static let shared = ScreenStates()

  static let handoffDuration: TimeInterval = 2

  final class Entry {
    let name: String
    fileprivate weak var scope: AnyObject?
    private weak var owner: AnyObject?
    private let hasOwner: Bool
    let model: AnyObject
    fileprivate var holders = 1
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

  private var entries: [Entry] = []
  private var handoff = 0
  private var handoffEnds = Date.distantPast
  private var handedOff: [Entry] = []

  func beginHandoff(in scope: AnyObject, now: Date = .now, endsItself: Bool = true) {
    handoff += 1
    handoffEnds = now.addingTimeInterval(Self.handoffDuration)
    entries.removeAll { $0.holders <= 0 }
    handedOff = entries.filter { $0.scope === scope }
    guard endsItself else { return }
    let current = handoff
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(Self.handoffDuration))
      self?.endHandoff(current)
    }
  }

  func endHandoff(_ ending: Int? = nil) {
    guard ending == nil || ending == handoff else { return }
    handedOff = []
    entries.removeAll { $0.holders <= 0 }
  }

  func lease<Model: AnyObject>(_ name: String, owner: AnyObject?, now: Date = .now, make: @escaping () -> Model) -> ScreenStateLease<Model> {
    if now < handoffEnds, let entry = unclaimed(name: name, owner: owner, as: Model.self), let model = entry.model as? Model {
      entry.holders += 1
      return ScreenStateLease(model: model, make: make, name: name, owner: owner, store: self, entry: entry, handoff: handoff)
    }
    return ScreenStateLease(model: make(), make: make, name: name, owner: owner, store: self, entry: nil, handoff: nil)
  }

  private func unclaimed<Model: AnyObject>(name: String, owner: AnyObject?, as _: Model.Type) -> Entry? {
    handedOff.first { $0.claimedIn != handoff && $0.matches(name: name, owner: owner) && $0.model is Model }
  }

  fileprivate func register(name: String, scope: AnyObject, owner: AnyObject?, model: AnyObject) -> Entry {
    let entry = Entry(name: name, scope: scope, owner: owner, model: model)
    entries.append(entry)
    return entry
  }

  fileprivate func takeOver<Model: AnyObject>(_ entry: Entry, from: Int, name: String, owner: AnyObject?, as _: Model.Type) -> Entry? {
    let current = from == handoff && entry.claimedIn != handoff
    guard let chosen = current ? entry : unclaimed(name: name, owner: owner, as: Model.self) else { return nil }
    chosen.claimedIn = handoff
    if chosen !== entry {
      chosen.holders += 1
    }
    if !entries.contains(where: { $0 === chosen }) {
      entries.append(chosen)
    }
    return chosen
  }

  fileprivate func release(_ entry: Entry) {
    entry.holders -= 1
    if entry.holders <= 0, !handedOff.contains(where: { $0 === entry }) {
      entries.removeAll { $0 === entry }
    }
  }

  func count(_ name: String) -> Int {
    entries.count { $0.name == name }
  }
}

@MainActor
@Observable
final class ScreenStateLease<Model: AnyObject> {
  private(set) var model: Model
  @ObservationIgnored private let make: () -> Model
  @ObservationIgnored private let name: String
  @ObservationIgnored private weak var owner: AnyObject?
  @ObservationIgnored private let store: ScreenStates?
  @ObservationIgnored private var entry: ScreenStates.Entry?
  @ObservationIgnored private var adopted = false
  @ObservationIgnored private var handedOver: Bool
  @ObservationIgnored private let handoff: Int?
  private(set) var settled = false

  fileprivate init(model: Model, make: @escaping () -> Model, name: String, owner: AnyObject?, store: ScreenStates?, entry: ScreenStates.Entry?, handoff: Int?) {
    self.model = model
    self.make = make
    self.name = name
    self.owner = owner
    self.store = store
    self.entry = entry
    self.handedOver = entry != nil
    self.handoff = handoff
  }

  convenience init(unshared model: Model) {
    self.init(model: model, make: { model }, name: "", owner: nil, store: nil, entry: nil, handoff: nil)
  }

  func adopt(in scope: AnyObject?) {
    defer {
      if !settled {
        settled = true
      }
    }
    guard !adopted, let store else { return }
    adopted = true
    if let candidate = entry, let handoff {
      if let taken = store.takeOver(candidate, from: handoff, name: name, owner: owner, as: Model.self), let takenModel = taken.model as? Model {
        if taken !== candidate {
          store.release(candidate)
          entry = taken
        }
        if takenModel !== model {
          model = takenModel
        }
        return
      }
      store.release(candidate)
      entry = nil
      handedOver = false
      model = make()
    }
    if let scope {
      entry = store.register(name: name, scope: scope, owner: owner, model: model)
    }
  }

  func takeHandedOver() -> Bool {
    defer { handedOver = false }
    return handedOver
  }

  deinit {
    guard let entry, let store else { return }
    Task { @MainActor in store.release(entry) }
  }
}

extension EnvironmentValues {
  @Entry var screenStateScope: AnyObject?
}
