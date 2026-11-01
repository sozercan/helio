//
//  MultiPostsView.swift
//  Helio
//
//  Created by Igor Marcossi on 20/08/23.
//

import Defaults
import SwiftUI

struct MultiPostsView: View {
  var multi: Multi

  @Environment(\.useTheme) private var selectedTheme
  @Environment(\.contentWidth) private var contentWidth
  ///  @Environment(\.colorScheme) private var cs
  @Default(.SubredditFeedDefSettings) var subFeedSettings

  func caller(_ lastElementId: String?, _ sorting: SubListingSortOption?, _ searchQuery: String?, _ flair: String?, _ context: FeedItemsManager<SubListingSortOption>.FetchContext) async -> ([RedditEntityType]?, String?)? {
    if let sorting, let result = await multi.fetchPosts(sort: sorting, after: lastElementId, contentWidth: contentWidth, limit: context.limit, altCredential: context.credential), let newPosts = result.0 {
      return (newPosts, result.1)
    }
    return nil
  }

  var body: some View {
    RedditListingFeed(feedId: multi.id, showSubInPosts: true, title: "\(subFeedSettings.showPrefixOnFeedTitle ? "m/" : "")\(multi.data?.name ?? "Multi")", theme: selectedTheme.postLinks.bg, fetch: caller, initialSorting: subFeedSettings.preferredSort, disableSearch: true, hideReadPosts: true)
  }
}
