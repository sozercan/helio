//
//  getItemId.swift
//  Helio
//
//  Created by Ethan Bills on 11/16/23.
//

import Foundation

func getItemId(for item: Either<Post, Comment>) -> String {
  // As per API doc: https://www.reddit.com/dev/api/#GET_user_{username}_overview
  switch item {
  case let .first(post):
    "\(Post.prefix)_\(post.id)"

  case let .second(comment):
    "\(Comment.prefix)_\(comment.id)"
  }
}
