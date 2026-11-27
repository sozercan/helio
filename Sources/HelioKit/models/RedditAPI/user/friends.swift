import Alamofire
import Foundation
import os

private let friendsLogger = Logger(subsystem: "com.sertacozercan.helio", category: "Friends")

struct RedditFriend: Codable, Hashable, Identifiable {
  let id: String
  let name: String
  let date: Double?
  let rel_id: String?
  let note: String?
}

struct RedditUserList: Codable, Hashable {
  let kind: String?
  let data: RedditUserListData?
}

struct RedditUserListData: Codable, Hashable {
  let children: [RedditFriend]?
}

extension RedditAPI {
  func fetchFriends(altCredential: RedditCredential? = nil) async -> [RedditFriend]? {
    let url = "\(RedditAPI.redditApiURLBase)/api/v1/me/friends"
    switch await self.doRequest(url, method: .get, decodable: RedditUserList.self, altCredential: altCredential) {
    case let .success(list):
      return list.data?.children ?? []
    case let .failure(error):
      friendsLogger.error("Failed to fetch friends: \(String(describing: error), privacy: .private)")
      return nil
    }
  }

  func setFriend(_ username: String, isFriend: Bool, altCredential: RedditCredential? = nil) async -> Bool {
    guard let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), !encoded.isEmpty else {
      return false
    }
    let url = "\(RedditAPI.redditApiURLBase)/api/v1/me/friends/\(encoded)"
    if isFriend {
      return await addFriend(url: url, username: username, altCredential: altCredential)
    } else {
      return await removeFriend(url: url, altCredential: altCredential)
    }
  }

  private func addFriend(url: String, username: String, altCredential: RedditCredential?) async -> Bool {
    let payload = AddFriendPayload(name: username)
    switch await self.doJSONRequest(url, method: .put, body: payload, altCredential: altCredential) {
    case .success:
      return true
    case let .failure(error):
      friendsLogger.error("Failed to add friend: \(String(describing: error), privacy: .private)")
      return false
    }
  }

  private func removeFriend(url: String, altCredential: RedditCredential?) async -> Bool {
    switch await self.doRequest(url, method: .delete, params: EmptyParameters(), paramsLocation: .queryString, altCredential: altCredential) {
    case .success:
      return true
    case let .failure(error):
      friendsLogger.error("Failed to remove friend: \(String(describing: error), privacy: .private)")
      return false
    }
  }

  private struct AddFriendPayload: Encodable {
    let name: String
  }

  private struct EmptyParameters: Encodable {}
}
