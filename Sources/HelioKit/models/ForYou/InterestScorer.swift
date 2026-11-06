//
//  InterestScorer.swift
//  Helio
//

import Foundation
import NaturalLanguage

/// How close a post title is to the posts the account upvoted and saved, from Apple's
/// on-device sentence embedding. Nothing leaves the device.
///
/// A title scores by its few nearest liked titles rather than the average of them all, so
/// someone into home servers and coffee gets both, not a blend of neither.
final class InterestScorer {
  private let embedding: NLEmbedding
  private let liked: [[Double]]
  private let neighbors = 3

  /// nil without the embedding (it ships for English) or any liked title it can read.
  init?(likedTitles: [String], embedding: NLEmbedding? = NLEmbedding.sentenceEmbedding(for: .english)) {
    guard let embedding else { return nil }
    let liked = likedTitles.compactMap { embedding.vector(for: $0).flatMap(Self.normalized) }
    guard !liked.isEmpty else { return nil }
    self.embedding = embedding
    self.liked = liked
  }

  /// From -1 to 1, higher is closer. nil when the title has no embedding.
  func score(_ title: String) -> Double? {
    guard let vector = embedding.vector(for: title).flatMap(Self.normalized) else { return nil }
    let similarities = liked.map { zip($0, vector).reduce(0) { $0 + $1.0 * $1.1 } }
    let nearest = similarities.sorted(by: >).prefix(neighbors)
    return nearest.reduce(0, +) / Double(nearest.count)
  }

  private static func normalized(_ vector: [Double]) -> [Double]? {
    let length = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
    guard length > 0 else { return nil }
    return vector.map { $0 / length }
  }
}
