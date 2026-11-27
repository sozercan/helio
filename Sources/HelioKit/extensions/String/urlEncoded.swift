import Foundation

extension String {
  var urlEncoded: String {
    self.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
  }
}
