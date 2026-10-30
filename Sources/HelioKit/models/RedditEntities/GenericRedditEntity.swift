//
//  GenericRedditEntity.swift
//  Helio
//
//  Created by Igor Marcossi on 30/06/23.
//

import Combine
import Defaults
import Foundation
import SwiftUI

protocol GenericRedditEntityDataType: Codable, Hashable, Identifiable {
  var id: String { get }
}

@Observable
class GenericRedditEntity<T: GenericRedditEntityDataType, B: Hashable>: Identifiable, Hashable, ObservableObject, Observable, Codable, Defaults.Serializable {
  func hash(into hasher: inout Hasher) {
//    hasher.combine(data)
//    hasher.combine(childrenHelio)
    hasher.combine(id)
    hasher.combine(typePrefix)
//    hasher.combine(data)
  }

  static func placeholder() -> GenericRedditEntity<T, B> {
    GenericRedditEntity<T, B>(id: "none", typePrefix: nil)
  }

  static func == (lhs: GenericRedditEntity<T, B>, rhs: GenericRedditEntity<T, B>) -> Bool {
    lhs.id == rhs.id && lhs.kind == rhs.kind && lhs.data?.id == rhs.data?.id
  }

  var data: T? {
    didSet {
      if let newID = data?.id, id != newID {
        self.id = newID
      }
    }
  }

  var selfPrefix: String {
    ""
  }

  var helioData: B? = nil
  var _id: String

  var id: String {
    get {
      self._id + self.kind
    }
    set {
      self._id = newValue
    }
  }

  var fullname: String {
    var actualTypePrefix = self.typePrefix ?? ""
    if actualTypePrefix.hasSuffix("_") {
      actualTypePrefix = String(actualTypePrefix.dropLast())
    }
    if id.hasPrefix("\(actualTypePrefix)_") {
      return id
    } else if id.hasPrefix("_") {
      return actualTypePrefix + id
    } else {
      return "\(actualTypePrefix)_\(id)"
    }
  }

  var loading = false
  var typePrefix: String?
  var kind: String?

  enum CodingKeys: CodingKey {
    case _id, loading, typePrefix, kind, data, childrenHelioData
  }

  required init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    _id = try container.decode(String.self, forKey: ._id)
    loading = try container.decode(Bool.self, forKey: .loading)
    typePrefix = try container.decodeIfPresent(String.self, forKey: .typePrefix)
    kind = try container.decodeIfPresent(String.self, forKey: .kind)
    data = try container.decodeIfPresent(T.self, forKey: .data)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(_id, forKey: ._id)
    try container.encode(loading, forKey: .loading)
    try container.encode(typePrefix, forKey: .typePrefix)
    try container.encode(kind, forKey: .kind)
    try container.encode(data, forKey: .data)
  }

  let redditAPI: RedditAPI = .shared
  var anyCancellables: [AnyCancellable]? = nil
  var childrenHelio: [GenericRedditEntity<T, B>] = []
  var parentHelio: [GenericRedditEntity<T, B>]?

  required init(id: String, typePrefix: String?) {
    self._id = id
    self.typePrefix = typePrefix
  }

  required init(data: T, typePrefix: String?) {
    self.data = data
    self._id = data.id
    self.typePrefix = typePrefix
  }

  init(data: T, typePrefix: String?, kind: String? = nil) {
    self.data = data
    self.kind = kind
    self._id = data.id
    self.typePrefix = typePrefix
  }

  func duplicate() -> GenericRedditEntity<T, B> {
    let copy = GenericRedditEntity<T, B>(id: id, typePrefix: typePrefix)
    copy.data = data
    copy.kind = kind
    copy.childrenHelio = childrenHelio
    return copy
  }

  func fetchItself() {
    Task(priority: .background) {
      if let data = await RedditAPI.shared.fetchInfo(fullnames: ["\(self.selfPrefix)_\(id)"]) {
        await MainActor.run { withAnimation {
          if let data = data as? T {
            self.data = data
          }
        } }
      }
    }
  }
}

enum RedditEntityType: Hashable, Equatable, Identifiable {
  case post(Post)
  case subreddit(Subreddit)
  case multi(Multi)
  case comment(Comment)
  case user(User)
  case message(Message)

  var fullname: String {
    switch self {
    case let .post(x): x.fullname
    case let .subreddit(x): x.fullname
    case let .multi(x): x.fullname
    case let .comment(x): x.fullname
    case let .user(x): x.fullname
    case let .message(x): x.fullname
    }
  }

  var id: String {
    switch self {
    case let .post(x): x.id
    case let .subreddit(x): x.id
    case let .multi(x): x.id
    case let .comment(x): x.id
    case let .user(x): x.id
    case let .message(x): x.id
    }
  }

  var selfPrefix: String {
    switch self {
    case let .post(x): x.selfPrefix
    case let .subreddit(x): x.selfPrefix
    case let .multi(x): x.selfPrefix
    case let .comment(x): x.selfPrefix
    case let .user(x): x.selfPrefix
    case let .message(x): x.selfPrefix
    }
  }
}
