//
//  fetchRelatedSubs.swift
//  Helio
//

import Foundation

extension RedditAPI {
  /// The communities a subreddit's sidebar lists, from its community-list widgets.
  func fetchRelatedSubs(_ subreddit: String, altCredential: RedditCredential? = nil) async -> [ForYouRelatedSub]? {
    guard let name = subreddit.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
    switch await doRequest("\(RedditAPI.redditApiURLBase)/r/\(name)/api/widgets", method: .get, decodable: SubredditWidgets.self, altCredential: altCredential) {
    case let .success(widgets):
      return widgets.items.values.flatMap(\.communities)
    case let .failure(error):
      forYouLogger.error("Couldn't load related subreddits: \(String(describing: error), privacy: .private)")
      return nil
    }
  }
}

/// Only the community lists: the other kinds of widget are skipped, as is any list in an
/// unexpected shape.
struct SubredditWidgets: Decodable {
  let items: [String: Widget]

  struct Widget: Decodable {
    let communities: [ForYouRelatedSub]

    private enum CodingKeys: String, CodingKey { case kind, data }

    init(from decoder: Decoder) throws {
      guard let container = try? decoder.container(keyedBy: CodingKeys.self),
            (try? container.decode(String.self, forKey: .kind)) == "community-list",
            let items = try? container.decode([LossyCommunity].self, forKey: .data)
      else {
        communities = []
        return
      }
      communities = items.compactMap(\.value)
    }
  }

  private struct LossyCommunity: Decodable {
    let value: ForYouRelatedSub?

    private enum CodingKeys: String, CodingKey { case name, subscribers, isNSFW }

    init(from decoder: Decoder) throws {
      guard let container = try? decoder.container(keyedBy: CodingKeys.self),
            let name = try? container.decode(String.self, forKey: .name), !name.isEmpty
      else {
        value = nil
        return
      }
      let subscribers = try? container.decode(Int.self, forKey: .subscribers)
      let over18 = (try? container.decode(Bool.self, forKey: .isNSFW)) ?? false
      value = ForYouRelatedSub(name: name, subscribers: subscribers, over18: over18)
    }
  }
}
