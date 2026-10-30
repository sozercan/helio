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
    var namesArr: [String] = []
    for subject in subjects {
      switch subject {
      case let .first(post):
        if let data = post.data, let fullname = data.author_fullname {
          namesArr.append(fullname)
        }
      case let .second(comment):
        if let data = comment.data, let fullname = data.author_fullname {
          namesArr.append(fullname)
        }
      }
    }
    if let avatarsDict = await updateAvatarURL(names: namesArr, avatarSize: avatarSize) {
      for subject in subjects {
        switch subject {
        case let .first(post):
          if let author = post.data?.author_fullname {
            DispatchQueue.main.async {
              post.helioData?.avatarImageRequest = avatarsDict[author]
            }
          }
        case let .second(comment):
          if let authorFullname = comment.data?.author_fullname {
            DispatchQueue.main.async { [avatarsDict] in
              comment.helioData?.avatarImageRequest = avatarsDict[authorFullname]
            }
          }
        }
      }
    }
  }

  func updateCommentsWithAvatar(comments: [Comment], avatarSize: Double, presentAvatarsDict: [String: ImageRequest]? = nil) async {
    let namesArr = presentAvatarsDict != nil ? [] : getNamesFromComments(comments)
    var avatarsDict: [String: ImageRequest] = presentAvatarsDict ?? [:]
    if avatarsDict.isEmpty, let newDict = await updateAvatarURL(names: namesArr, avatarSize: avatarSize) {
      avatarsDict = newDict
    }
    for comment in comments {
      if let authorFullname = comment.data?.author_fullname {
        DispatchQueue.main.async { [avatarsDict] in
          comment.helioData?.avatarImageRequest = avatarsDict[authorFullname]
        }
      }
      Task { [avatarsDict] in await self.updateCommentsWithAvatar(comments: comment.childrenHelio, avatarSize: avatarSize, presentAvatarsDict: avatarsDict) }
    }
  }

  func updatePostsWithAvatar(posts: [Post], avatarSize: Double) async {
    let namesArr = posts.compactMap { $0.data?.author_fullname }
    if let avatarsDict = await updateAvatarURL(names: namesArr, avatarSize: avatarSize) {
      for post in posts {
        if let author = post.data?.author_fullname {
          DispatchQueue.main.async { [avatarsDict] in
            post.helioData?.avatarImageRequest = avatarsDict[author]
          }
        }
      }
    }
  }

  func updateAvatarURL(names: [String], avatarSize: Double) async -> [String: ImageRequest]? {
    let nonHelioAppNames = names.filter { $0 != SAMPLE_USER_AVATAR }
    var returnDict: [String: ImageRequest] = [:]
    returnDict[SAMPLE_USER_AVATAR] = ImageRequest(stringLiteral: "https://raw.githubusercontent.com/sozercan/helio/main/App/Helio/Assets.xcassets/appIcons/iconStandard.appiconset/iconStandard.png")

    if !nonHelioAppNames.isEmpty, let data = await self.fetchUsers(nonHelioAppNames) {
      //      let avatarSize = Defaults[]
      let newDict = data.compactMapValues { val in
        if let urlStr = val.profile_img, let url = URL(string: String(urlStr.split(separator: "?")[0])) {
          //          let userInfoKey = ImageRequest.UserInfoKey()
          //          ImageProcessing
//          let thumbOpt = ImageRequest.ThumbnailOptions(size: .init(width: avatarSize, height: avatarSize), unit: .points, contentMode: .aspectFill)
//          let req = ImageRequest(url: url, processors: [ImageProcessors.ScaleFixer()], priority: .veryHigh, userInfo: [.thumbnailKey: thumbOpt])
          return ImageRequest(url: url, processors: [ImageProcessors.Resize(width: avatarSize), ImageProcessors.ScaleFixer()], priority: .veryHigh)
        }
        return nil
      }

      return newDict.merging(returnDict) { x, _ in x }
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

func getNamesFromComments(_ comments: [Comment]) -> [String] {
  var namesArr: [String] = []
  for comment in comments {
    if let fullname = comment.data?.author_fullname {
      namesArr.append(fullname)
    }
    namesArr += getNamesFromComments(comment.childrenHelio)
  }
  return namesArr
}
