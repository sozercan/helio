import Alamofire
import Foundation

extension RedditAPI {
  func fetchUser(_ userName: String, altCredential: RedditCredential? = nil) async -> UserData? {
    switch await self.doRequest("\(RedditAPI.redditApiURLBase)/user/\(userName)/about.json", method: .get, decodable: ListingChild<UserData>.self, altCredential: altCredential) {
    case let .success(data):
      return data.data
    case let .failure(error):
      print(error)
      return nil
    }
  }
}
