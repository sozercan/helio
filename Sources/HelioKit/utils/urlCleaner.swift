import Foundation

func cleanURL(url: URL, showPath: Bool = true) -> String {
  var newURL = ""

  if let host = url.host?.replacingOccurrences(of: "www.", with: "") {
    newURL = host
  }

  if showPath {
    if !url.path.isEmpty {
      newURL += url.path()
    }
  }

  if newURL.isEmpty {
    newURL = "Invalid URL"
  }

  return newURL
}
