//
//  CommentSample.swift
//  Helio
//
//  Created by Igor Marcossi on 16/09/23.
//

import Foundation

func getCommentSampleData(_ withChild: Bool = true) -> CommentData {
  var commentSampleData = CommentData(id: "helioSample")
  commentSampleData.author = "Helio"
  commentSampleData.author_fullname = "t2_helio_empty_sample"
  commentSampleData.author_flair_text = "flair"
  commentSampleData.body = "My best friend was called apollo, but he passed away a few ago :("
  commentSampleData.created = Date().timeIntervalSince1970 - 115200
  commentSampleData.ups = 483
  if withChild {
    var listingChild = ListingChild<CommentData>(kind: "Comment")
    listingChild.data = getCommentSampleData(false)
    var listingData = ListingData<CommentData>(after: nil, dist: nil, modhash: nil, geo_filter: nil)
    listingData.children = [listingChild]
    var listing = Listing<CommentData>(kind: "comment")
    listing.data = listingData
    commentSampleData.replies = .second(listing)
  }
  return commentSampleData
}

let commentSample = Comment(data: getCommentSampleData())
