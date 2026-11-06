//
//  HelioTheme.swift
//  Helio
//
//  Created by Igor Marcossi on 07/09/23.
//

import Defaults
import Foundation
import SwiftUI

struct HelioTheme: Codable, Identifiable, Hashable, Equatable, Defaults.Serializable {
  enum CodingKeys: String, CodingKey {
    case metadata, id, postLinks, posts, comments, lists, general
  }

  /// The theme's parts, in a box that copies share until one of them is changed. A theme is
  /// nearly 4KB, and every view that reads it from the environment (`useTheme`) holds the whole
  /// value: such views were as big, and SwiftUI copies views on the stack as it updates them.
  /// Deep in a layout, as after rotating, that ran Debug builds out of main-thread stack.
  private final class Parts {
    var metadata: HelioThemeMeta
    var id: String
    var postLinks: SubPostsListTheme
    var posts: PostTheme
    var comments: CommentsSectionTheme
    var lists: ListsTheme
    var general: GeneralTheme

    init(metadata: HelioThemeMeta, id: String, postLinks: SubPostsListTheme, posts: PostTheme, comments: CommentsSectionTheme, lists: ListsTheme, general: GeneralTheme) {
      self.metadata = metadata
      self.id = id
      self.postLinks = postLinks
      self.posts = posts
      self.comments = comments
      self.lists = lists
      self.general = general
    }

    func copy() -> Parts {
      Parts(metadata: metadata, id: id, postLinks: postLinks, posts: posts, comments: comments, lists: lists, general: general)
    }
  }

  private var parts: Parts

  var metadata: HelioThemeMeta {
    get { parts.metadata }
    set { uniqueParts().metadata = newValue }
  }

  var id: String {
    get { parts.id }
    set { uniqueParts().id = newValue }
  }

  var postLinks: SubPostsListTheme {
    get { parts.postLinks }
    set { uniqueParts().postLinks = newValue }
  }

  var posts: PostTheme {
    get { parts.posts }
    set { uniqueParts().posts = newValue }
  }

  var comments: CommentsSectionTheme {
    get { parts.comments }
    set { uniqueParts().comments = newValue }
  }

  var lists: ListsTheme {
    get { parts.lists }
    set { uniqueParts().lists = newValue }
  }

  var general: GeneralTheme {
    get { parts.general }
    set { uniqueParts().general = newValue }
  }

  /// The parts, copied first if another theme shares them.
  private mutating func uniqueParts() -> Parts {
    if !isKnownUniquelyReferenced(&parts) {
      parts = parts.copy()
    }
    return parts
  }

  static func == (lhs: HelioTheme, rhs: HelioTheme) -> Bool {
    lhs.parts === rhs.parts || (lhs.metadata == rhs.metadata && lhs.id == rhs.id && lhs.postLinks == rhs.postLinks && lhs.posts == rhs.posts && lhs.comments == rhs.comments && lhs.lists == rhs.lists && lhs.general == rhs.general)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(metadata)
    hasher.combine(id)
    hasher.combine(postLinks)
    hasher.combine(posts)
    hasher.combine(comments)
    hasher.combine(lists)
    hasher.combine(general)
  }

  func save() {
    guard let index = Defaults[.ThemesDefSettings].themesPresets.firstIndex(where: { $0.id == self.id }) else { return }
    Defaults[.ThemesDefSettings].themesPresets[index] = self
  }

  func duplicate() -> HelioTheme {
    var copy = self
    copy.id = UUID().uuidString
    if copy.metadata.name == "Default" {
      copy.metadata.name = randomWord().capitalized
    }
    return copy
  }

  init(
    metadata: HelioThemeMeta = HelioThemeMeta(),
    id: String = UUID().uuidString,
    postLinks: SubPostsListTheme,
    posts: PostTheme,
    comments: CommentsSectionTheme,
    lists: ListsTheme,
    general: GeneralTheme,
  ) {
    parts = Parts(metadata: metadata, id: id, postLinks: postLinks, posts: posts, comments: comments, lists: lists, general: general)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(metadata, forKey: .metadata)
    try container.encodeIfPresent(id, forKey: .id)
    try container.encodeIfPresent(postLinks, forKey: .postLinks)
    try container.encodeIfPresent(posts, forKey: .posts)
    try container.encodeIfPresent(comments, forKey: .comments)
    try container.encodeIfPresent(lists, forKey: .lists)
    try container.encodeIfPresent(general, forKey: .general)
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      metadata: container.decode(HelioThemeMeta.self, forKey: .metadata),
      id: container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
      postLinks: container.decodeIfPresent(SubPostsListTheme.self, forKey: .postLinks) ?? defaultTheme.postLinks,
      posts: container.decodeIfPresent(PostTheme.self, forKey: .posts) ?? defaultTheme.posts,
      comments: container.decodeIfPresent(CommentsSectionTheme.self, forKey: .comments) ?? defaultTheme.comments,
      lists: container.decodeIfPresent(ListsTheme.self, forKey: .lists) ?? defaultTheme.lists,
      general: container.decodeIfPresent(GeneralTheme.self, forKey: .general) ?? defaultTheme.general,
    )
  }
}
