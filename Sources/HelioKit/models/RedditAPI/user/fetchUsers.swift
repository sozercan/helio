//
//  fetchUsers.swift
//  Helio
//
//  Created by Igor Marcossi on 04/07/23.
//

import Alamofire
import Defaults
import Foundation
import Nuke
import NukeUI
import SwiftUI

extension RedditAPI {
  func fetchUsers(_ ids: [String]) async -> MultipleUsersDictionary? {
    let payload = FetchUsersByIDPayload(ids: String(ids.joined(separator: ",")))
    switch await self.doRequest("\(RedditAPI.redditApiURLBase)/api/user_data_by_account_ids", method: .get, params: payload, paramsLocation: .queryString, decodable: MultipleUsersDictionary.self) {
    case let .success(data):
      return data
    case let .failure(error):
      print(error)
      return nil
    }
  }

  func updateOverviewSubjectsWithAvatar(subjects: [Either<Post, Comment>], avatarSize: Double) async {
    let names = subjects.compactMap { subject in
      switch subject {
      case let .first(post): post.data?.author_fullname
      case let .second(comment): comment.data?.author_fullname
      }
    }
    let avatarsDict = await updateAvatarURL(names: names, avatarSize: avatarSize)
    await MainActor.run {
      for subject in subjects {
        switch subject {
        case let .first(post):
          if let author = post.data?.author_fullname {
            post.helioData?.avatarImageRequest = avatarsDict[author]
          }
        case let .second(comment):
          if let author = comment.data?.author_fullname {
            comment.helioData?.avatarImageRequest = avatarsDict[author]
          }
        }
      }
    }
  }

  /// Sets the avatars of the comments and all their replies, with one lookup and one main-queue
  /// hop for the whole tree.
  func updateCommentsWithAvatar(comments: [Comment], avatarSize: Double) async {
    var all: [Comment] = []
    func walk(_ comments: [Comment]) {
      for comment in comments {
        all.append(comment)
        walk(comment.childrenHelio)
      }
    }
    walk(comments)
    let tree = all
    let avatarsDict = await updateAvatarURL(names: tree.compactMap { $0.data?.author_fullname }, avatarSize: avatarSize)
    await MainActor.run {
      for comment in tree {
        if let author = comment.data?.author_fullname {
          comment.helioData?.avatarImageRequest = avatarsDict[author]
        }
      }
    }
  }

  func updatePostsWithAvatar(posts: [Post], avatarSize: Double) async {
    let avatarsDict = await updateAvatarURL(names: posts.compactMap { $0.data?.author_fullname }, avatarSize: avatarSize)
    await MainActor.run {
      for post in posts {
        if let author = post.data?.author_fullname {
          post.helioData?.avatarImageRequest = avatarsDict[author]
        }
      }
    }
  }

  func updateAvatarURL(names: [String], avatarSize: Double) async -> [String: ImageRequest] {
    var returnDict: [String: ImageRequest] = [:]
    returnDict[SAMPLE_USER_AVATAR] = ImageRequest(stringLiteral: "https://raw.githubusercontent.com/sozercan/helio/main/App/Helio/Assets.xcassets/appIcons/iconStandard.appiconset/iconStandard.png")
    let urls = await AvatarLoader.shared.avatarURLs(for: names.filter { $0 != SAMPLE_USER_AVATAR })
    for (name, url) in urls {
      returnDict[name] = ImageRequest(url: url, processors: [ImageProcessors.Resize(width: avatarSize), ImageProcessors.ScaleFixer()], priority: .veryHigh)
    }
    return returnDict
  }

  struct FetchUsersByIDPayload: Codable {
    let ids: String
    var raw_json = 1
  }

  typealias MultipleUsersDictionary = [String: MultipleUsersUser]

  struct MultipleUsersUser: Codable {
    let name: String?
    let created_utc: Double?
    let link_karma: Int?
    let comment_karma: Int?
    let profile_img: String?
    let profile_color: String?
    let profile_over_18: Bool?
  }
}
