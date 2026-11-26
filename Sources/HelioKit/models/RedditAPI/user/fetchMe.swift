import Alamofire
import Foundation

extension RedditAPI {
  func fetchMe(altCredential: RedditCredential? = nil, saveToken: Bool = true) async -> UserData? {
    switch await doRequest("\(RedditAPI.redditApiURLBase)/api/v1/me", method: .get, decodable: UserData.self, altCredential: altCredential, saveToken: saveToken) {
    case let .success(data): data
    case .failure: nil
    }
  }
}
