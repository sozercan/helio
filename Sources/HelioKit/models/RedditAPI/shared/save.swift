import Alamofire
import Foundation

extension RedditAPI {
  func save(_ action: Bool, id: String) async -> Bool? {
    let params = SavePayload(id: id)
    switch await self.doRequest("\(RedditAPI.redditApiURLBase)/api/\(action ? "save" : "unsave")?raw_json=1", method: .post, params: params) {
    case .success:
      return true
    case .failure:
      return nil
    }
  }

  struct SavePayload: Codable {
    let id: String
  }
}
