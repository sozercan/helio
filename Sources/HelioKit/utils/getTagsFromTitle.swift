//
//  getTagsFromTitle.swift
//  Helio
//
//  Created by Igor Marcossi on 23/10/23.
//

import Foundation
import SwiftUI
import UIKit

func getTagsFromTitle(_ data: PostData) -> [PrependTag] {
  getTagsFromTitleRaw(data)
}

func getTagsFromTitleRaw(_ data: PostData) -> [PrependTag] {
  var tags: [PrependTag] = []
  if data.over_18 ?? false {
    tags.append(.init(label: "NSFW", bgColor: UIColor(.red.opacity(0.9)), textColor: .white))
  }
  if let flair = Post.extractFlairData(data: data) {
    tags.append(flair)
  }
  return tags
}
