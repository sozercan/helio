import Foundation

final class ExpiringCache<Value>: @unchecked Sendable {
  private final class Entry {
    let value: Value
    let expiresAt: Date?

    init(value: Value, expiresAt: Date?) {
      self.value = value
      self.expiresAt = expiresAt
    }
  }

  private let storage = NSCache<NSString, Entry>()

  init(countLimit: Int) {
    storage.countLimit = countLimit
  }

  func get(key: String, now: Date = Date()) -> Value? {
    let nsKey = key as NSString
    guard let entry = storage.object(forKey: nsKey) else { return nil }
    if let expiresAt = entry.expiresAt, now >= expiresAt {
      storage.removeObject(forKey: nsKey)
      return nil
    }
    return entry.value
  }

  func set(key: String, value: Value, expiresAt: Date? = nil) {
    storage.setObject(Entry(value: value, expiresAt: expiresAt), forKey: key as NSString)
  }

  func removeAll() {
    storage.removeAllObjects()
  }
}

enum Caches {
  static let streamable = ExpiringCache<StreamableCached>(countLimit: 100)
}
