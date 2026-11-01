//
//  updatePostsInBox.swift
//  Helio
//
//  Created by Igor Marcossi on 25/07/23.
//

import CoreData
import Defaults
import Foundation
import SwiftUI

func updatePostsInBox(force: Bool = false) async {
  let postsInBox = Defaults[.postsInBox]
  let postsInBoxNames: [String] = postsInBox.compactMap { post in
    if let lastRefresh = post.lastUpdatedAt, !force, Date().timeIntervalSince1970 - lastRefresh < 120 {
      return nil
    }
    return post.fullname
  }
  guard !postsInBoxNames.isEmpty else { return }
  if let posts = await RedditAPI.shared.fetchPosts(postFullnames: postsInBoxNames) {
    var postsDict: [String: PostData] = [:]
    for data in posts {
      postsDict[data.name] = data
    }

    var newPostsInBox = postsInBox.map { post in
      var newPost = post
      if let newData = postsDict[post.fullname] {
        newPost.score = newData.ups
        newPost.commentsCount = newData.num_comments
      }
      return newPost
    }

    let context = PersistenceController.shared.container.newBackgroundContext()
    let fetchRequest = NSFetchRequest<SeenPost>(entityName: "SeenPost")
    fetchRequest.predicate = NSPredicate(format: "postID IN %@", postsInBox.map(\.id))
    if let results = await (context.perform(schedule: .enqueued) { try? context.fetch(fetchRequest) }) {
      await context.perform(schedule: .enqueued) {
        newPostsInBox = postsInBox.map { post in
          var newPost = post

          if let foundPost = results.first(where: { obj in obj.postID == post.id }), let numComments = post.commentsCount {
            newPost.newCommentsCount = numComments - Int(foundPost.numComments)
          }

          return newPost
        }
      }
    }

    await MainActor.run { [newPostsInBox] in
      withAnimation {
        Defaults[.postsInBox] = newPostsInBox
      }
    }
  }
}
