//
//  PostFloatingPill.swift
//  Helio
//
//  Created by Igor Marcossi on 06/07/23.
//

import AlertToast
import Defaults
import SwiftUI

struct PostFloatingPill: View {
  var post: Post
  var subreddit: Subreddit
  var updateComments: (() -> Void)?
  var showUpVoteRatio: Bool

  @Default(.postsInBox) private var postsInBox
  @Environment(\.useTheme) private var selectedTheme
  @State private var showReplyModal = false
  @State private var showAddedToast: Bool = false
  @State private var showRemovedToast: Bool = false
  private var thisPinnedPost: Bool {
    postsInBox.contains { $0.id == post.id }
  }

  private var boxLabel: String {
    thisPinnedPost ? "Remove from Posts Box" : "Add to Posts Box"
  }

  private var boxIcon: String {
    thisPinnedPost ? "shippingbox.and.arrow.backward.fill" : "shippingbox"
  }

  private func togglePostsBox(_ data: PostData) {
    if thisPinnedPost {
      withAnimation(spring) {
        postsInBox = postsInBox.filter { $0.id != post.id }
      }
      withAnimation(nil) {
        showRemovedToast.toggle()
      }
    } else {
      var subIcon: String?
      if let subData = subreddit.data {
        let communityIcon = subData.community_icon?.split(separator: "?") ?? []
        subIcon = (subData.icon_img ?? "").isEmpty ? !communityIcon.isEmpty ? String(communityIcon[0]) : "" : subData.icon_img
      }
      let newPostInBox = PostInBox(
        id: data.id, fullname: data.name,
        title: data.title, body: data.selftext ?? "",
        subredditIconURL: subIcon, img: nil,
        subredditName: data.subreddit, authorName: data.author,
        score: data.ups, commentsCount: data.num_comments,
        createdAt: data.created, lastUpdatedAt: Date().timeIntervalSince1970,
      )
      withAnimation(spring) {
        postsInBox.append(newPostInBox)
      }
      withAnimation(nil) {
        showAddedToast.toggle()
      }
    }
  }

  /// The box icon alone doesn't say what it does: the pointer and a long press name it.
  private func postsBoxButton(_ data: PostData) -> some View {
    LightBoxButton(icon: boxIcon, label: boxLabel) { togglePostsBox(data) }
      .help(boxLabel)
      .contextMenu {
        Button(boxLabel, systemImage: boxIcon) { togglePostsBox(data) }
      }
  }

  var body: some View {
    Group {
      if let data = post.data {
        let permalink = "https://reddit.com\(data.permalink.urlEncoded)"

        if !selectedTheme.posts.inlineFloatingPill {
          // The post page's bottom bar: monochrome icons on glass, like the system's bars.
          HStack(spacing: 2) {
            HStack(spacing: -12) {
              LightBoxButton(icon: "square.and.arrow.up", label: "Share") {
                ShareUtils.shareItem(item: permalink)
              }

              postsBoxButton(data)

              LightBoxButton(icon: "arrowshape.turn.up.left", label: "Reply") {
                withAnimation(spring) {
                  showReplyModal = true
                }
              }
            }

            VotesCluster(votesKit: data.votesKit, voteAction: post.vote, vertical: false, showUpVoteRatio: showUpVoteRatio)
          }
          .padding(.trailing, 14)
          .foregroundStyle(.primary)
          .floating()
        } else {
          HStack { // Set spacing to 0 to make buttons stretch evenly
            LightBoxButton(icon: data.saved ? "bookmark.fill" : "bookmark", label: data.saved ? "Unsave" : "Save") {
              Task {
                await post.saveToggle()
              }
            }
            .padding(.vertical, -2)

            Spacer()

            LightBoxButton(icon: "square.and.arrow.up.fill", label: "Share") {
              ShareUtils.shareItem(item: permalink)
            }
            .padding(.vertical, -2)

            Spacer()

            postsBoxButton(data)
              .padding(.vertical, -2)

            Spacer()

            LightBoxButton(icon: "arrowshape.turn.up.left.fill", label: "Reply") {
              withAnimation(spring) {
                showReplyModal = true
              }
            }
            .padding(.vertical, -2)

            Spacer()

            VotesCluster(votesKit: data.votesKit, voteAction: post.vote, vertical: false, showUpVoteRatio: showUpVoteRatio)
              .padding(.vertical, -2)

            Spacer()
          }
          .foregroundStyle(Color.accentColor)
          .background(RR(12, selectedTheme.comments.theme.bg()))
          .frame(maxWidth: .infinity)
        }
      }
    }
    .fontSize(20, .semibold)
    .sheet(isPresented: $showReplyModal) {
      ReplyModalPost(post: post, updateComments: updateComments)
    }
  }
}
