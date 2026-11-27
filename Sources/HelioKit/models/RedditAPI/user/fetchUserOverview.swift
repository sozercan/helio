import Alamofire
import Defaults
import Foundation
import os

private let userOverviewLogger = Logger(subsystem: "com.sertacozercan.helio", category: "UserOverview")

enum UserListingSection: String, CaseIterable, Hashable, Identifiable {
  case overview
  case submitted
  case comments
  case upvoted
  case downvoted
  case saved
  case hidden

  var id: String {
    rawValue
  }

  static let publicSections: [Self] = [.overview, .submitted, .comments]
  static let ownSections: [Self] = Self.allCases

  var label: String {
    switch self {
    case .overview: "Overview"
    case .submitted: "Posts"
    case .comments: "Comments"
    case .upvoted: "Upvoted"
    case .downvoted: "Downvoted"
    case .saved: "Saved"
    case .hidden: "Hidden"
    }
  }

  var heading: String {
    switch self {
    case .overview: "Latest activity"
    case .submitted: "Latest posts"
    case .comments: "Latest comments"
    case .upvoted: "Upvoted"
    case .downvoted: "Downvoted"
    case .saved: "Saved"
    case .hidden: "Hidden"
    }
  }

  var systemImage: String {
    switch self {
    case .overview: "clock"
    case .submitted: "doc.text"
    case .comments: "bubble.left"
    case .upvoted: "arrow.up"
    case .downvoted: "arrow.down"
    case .saved: "bookmark"
    case .hidden: "eye.slash"
    }
  }

  var endpointSegment: String {
    rawValue
  }

  var isPrivate: Bool {
    switch self {
    case .overview, .submitted, .comments: false
    case .upvoted, .downvoted, .saved, .hidden: true
    }
  }
}

extension RedditAPI {
  func fetchUserOverview(
    _ userName: String,
    section: UserListingSection = .overview,
    _ after: String? = nil,
    limit: Int = Defaults[.SubredditFeedDefSettings].chunkLoadSize,
    altCredential: RedditCredential? = nil,
  ) async -> ([Either<PostData, CommentData>]?, String?)? {
    guard let encodedName = userName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), !encodedName.isEmpty else {
      return nil
    }
    let endpoint = "\(RedditAPI.redditApiURLBase)/user/\(encodedName)/\(section.endpointSegment).json"
    guard var urlComponents = URLComponents(string: endpoint) else {
      userOverviewLogger.error("Unable to create a valid URL for user listing section \(section.rawValue, privacy: .public)")
      return nil
    }

    urlComponents.queryItems = [URLQueryItem(name: "limit", value: "\(limit)")]
    if let after {
      urlComponents.queryItems?.append(URLQueryItem(name: "after", value: after))
    }

    guard let requestURL = urlComponents.url else {
      userOverviewLogger.error("Unable to create a valid URL for user listing section \(section.rawValue, privacy: .public)")
      return nil
    }

    switch await self.doRequest(requestURL.absoluteString, method: .get, decodable: Listing<Either<PostData, CommentData>>.self, altCredential: altCredential) {
    case let .success(data):
      return (data.data?.children?.map(\.data).compactMap(\.self), data.data?.after)
    case let .failure(error):
      userOverviewLogger.error("Failed to fetch user listing \(section.rawValue, privacy: .public): \(String(describing: error), privacy: .private)")
      return nil
    }
  }
}
