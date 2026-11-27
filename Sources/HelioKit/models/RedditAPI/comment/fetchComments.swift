import Alamofire
import Foundation

extension RedditAPI {
  func fetchPost(subreddit: String, postID: String, commentID: String? = nil, sort: CommentSortOption = .confidence) async -> FetchPostCommentsResponse? {
    let params = FetchPostCommentsPayload(sort: sort.rawVal.value, limit: 35, depth: 15)
    var specificComment = ""
    if let commentID {
      specificComment = "/comment/\(commentID.hasPrefix("t1_") ? String(commentID.dropFirst(3)) : commentID)"
    }
    switch await self.doRequest(
      "\(RedditAPI.redditApiURLBase)/r/\(subreddit)/comments/\(postID.hasPrefix("t3_") ? String(postID.dropFirst(3)) : postID)\(specificComment).json",
      method: .get,
      params: params,
      paramsLocation: .queryString,
      decodable: FetchPostCommentsResponse.self,
      webSessionAuth: .cookie(host: "www.reddit.com"),
    ) {
    case let .success(data):
      return data
    case let .failure(error):
      print(error)
      return nil
    }
  }

  struct FetchPostCommentsResponse: Decodable {
    let post: Listing<PostData>?
    let comments: Listing<CommentData>?

    init(from decoder: Decoder) throws {
      var container = try decoder.unkeyedContainer()
      post = container.isAtEnd ? nil : try container.decode(Listing<PostData>?.self)
      comments = container.isAtEnd ? nil : try container.decode(Listing<CommentData>?.self)
    }
  }

  struct FetchPostCommentsPayload: Codable {
    var sort: String
    var limit: Int
    var depth: Int
    var comment: String?
    var raw_json = 1
  }
}
