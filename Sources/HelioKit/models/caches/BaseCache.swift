//
//  BaseCache.swift
//  Helio
//
//  Created by Igor Marcossi on 20/09/23.
//

import Combine
import Foundation
import SwiftUI

struct CacheItem<T>: Identifiable, Equatable {
  static func == (lhs: CacheItem<T>, rhs: CacheItem<T>) -> Bool {
    lhs.id == rhs.id
  }

  let id = UUID()
  let data: T
  let createdAt: Date
  let eternal: Bool = false
  var expires: Date?
}

class BaseCache<T: Any>: ObservableObject {
  @Published var cache: [String: CacheItem<T>] = [:]
  let cacheLimit: Int
  /// Optional teardown run (on the main actor) for the item evicted when the cache overflows.
  var onEvict: ((T) -> Void)?

  init(cacheLimit: Int = 50, cache: [String: CacheItem<T>] = [:]) {
    self.cacheLimit = cacheLimit
    self.cache = cache
  }

  func get(key: String) -> T? {
    if let cacheItem = cache[key], cacheItem.expires == nil || Date() < cacheItem.expires! {
      return cacheItem.data
    }

    return nil
  }

  func addKeyValue(key: String, data: @escaping () -> T, expires: Date? = nil) {
    if cache[key] != nil {
      return
    }
    Task(priority: .background) {
      let itemData = data()
      let item = CacheItem(data: itemData, createdAt: Date(), expires: expires)
      let allowedToRemoveCacheList = cache.filter { !$0.value.eternal }
      let oldestKey = cache.count > cacheLimit ? allowedToRemoveCacheList.min { a, b in a.value.createdAt < b.value.createdAt }?.key : nil

      await MainActor.run {
        var evicted: T? = nil
        withAnimation {
          cache[key] = item
          if let oldestKey {
            evicted = cache.removeValue(forKey: oldestKey)?.data
          }
        }
        if let evicted {
          onEvict?(evicted)
        }
      }
    }
  }

  func merge(_ dict: [String: T]) async {
    let newDict = dict.mapValues { CacheItem(data: $0, createdAt: Date()) }
    let allowedToRemoveCacheList = cache.filter { !$0.value.eternal }
    await MainActor.run {
      withAnimation {
        cache.merge(newDict) { _, new in new }
      }
      while cache.count > cacheLimit {
        guard let oldestKey = allowedToRemoveCacheList.min(by: { a, b in a.value.createdAt < b.value.createdAt })?.key else { return }
        cache.removeValue(forKey: oldestKey)
      }
    }
  }
}

class BaseObservableCache<T: ObservableObject>: ObservableObject {
  @Published var cache: [String: CacheItem<T>] = [:]
  let cacheLimit: Int

  init(cacheLimit: Int = 50, cache: [String: CacheItem<T>] = [:]) {
    self.cacheLimit = cacheLimit
    self.cache = cache
  }

  func get(key: String) -> T? {
    cache[key]?.data
  }

  func addKeyValue(key: String, data: @escaping () -> T, expires: Date? = nil) {
    if cache[key] != nil {
      return
    }
    Task(priority: .background) {
      let itemData = data()
      // Create a new CacheItem with the current date
      let item = CacheItem(data: itemData, createdAt: Date(), expires: expires)
      let allowedToRemoveCacheList = cache.filter { !$0.value.eternal }
      let oldestKey = cache.count > cacheLimit ? allowedToRemoveCacheList.min { a, b in a.value.createdAt < b.value.createdAt }?.key : nil

      // Add the item to the cache
      await MainActor.run {
        withAnimation {
          cache[key] = item
          if let oldestKey {
            cache.removeValue(forKey: oldestKey)
          }
        }
      }
    }
  }
}
