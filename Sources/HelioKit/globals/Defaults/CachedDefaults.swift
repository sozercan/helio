//
//  CachedDefaults.swift
//  Helio
//

import Defaults
import Foundation
import Synchronization

/// Decoded settings, kept until any user default changes. `Defaults[key]` decodes the stored
/// JSON on every read, and laying a post out reads settings several times, often on the main
/// queue while the feed scrolls.
enum CachedDefaults {
  private struct State {
    var values: [String: Any] = [:]
    var generation = 0
  }

  private static let state = Mutex(State())
  private static let observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { _ in
    state.withLock {
      $0.values.removeAll()
      $0.generation += 1
    }
  }

  static subscript<Value: Defaults.Serializable>(key: Defaults.Key<Value>) -> Value {
    _ = observer
    let (cached, readGeneration) = state.withLock { ($0.values[key.name] as? Value, $0.generation) }
    if let cached {
      return cached
    }
    let value = Defaults[key]
    state.withLock {
      // A change while decoding would otherwise leave the old value cached.
      if $0.generation == readGeneration {
        $0.values[key.name] = value
      }
    }
    return value
  }
}
