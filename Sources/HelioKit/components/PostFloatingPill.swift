//
//  PostFloatingPill.swift
//  Helio
//
//  Created by Igor Marcossi on 06/07/23.
//

import SwiftUI

struct PostFloatingPill: View {
  var post: Post
  var subreddit: Subreddit
  var updateComments: (() -> Void)?
  var showUpVoteRatio: Bool
  /// Narrow windows: Share, Save and Reply fold into one menu so the votes stay in reach.
  var compact: Bool = false

  @Environment(\.useTheme) private var selectedTheme
  @State private var showReplyModal = false

  private func saveLabel(_ data: PostData) -> String {
    data.saved ? "Unsave" : "Save"
  }

  private func saveIcon(_ data: PostData) -> String {
    data.saved ? "bookmark.fill" : "bookmark"
  }

  private func toggleSave() {
    Task { await post.saveToggle() }
  }

  var body: some View {
    Group {
      if let data = post.data {
        let permalink = "https://reddit.com\(data.permalink.urlEncoded)"

        if !selectedTheme.posts.inlineFloatingPill {
          // The post page's bottom bar: monochrome icons on glass, like the system's bars.
          HStack(spacing: 2) {
            if compact {
              Menu {
                Button("Share", systemImage: "square.and.arrow.up") {
                  ShareUtils.shareItem(item: permalink)
                }
                Button(saveLabel(data), systemImage: saveIcon(data)) { toggleSave() }
                Button("Reply", systemImage: "arrowshape.turn.up.left") {
                  withAnimation(spring) {
                    showReplyModal = true
                  }
                }
              } label: {
                Image(systemName: "ellipsis")
                  .frame(width: 44, height: 44)
                  .contentShape(Rectangle())
              }
              .menuStyle(.button)
              .buttonStyle(.plain)
              .accessibilityLabel("Post actions")
              .help("Post actions")
            } else {
              HStack(spacing: -12) {
                LightBoxButton(icon: "square.and.arrow.up", label: "Share") {
                  ShareUtils.shareItem(item: permalink)
                }

                LightBoxButton(icon: saveIcon(data), label: saveLabel(data)) { toggleSave() }

                LightBoxButton(icon: "arrowshape.turn.up.left", label: "Reply") {
                  withAnimation(spring) {
                    showReplyModal = true
                  }
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
            LightBoxButton(icon: saveIcon(data), label: saveLabel(data)) { toggleSave() }
              .padding(.vertical, -2)

            Spacer()

            LightBoxButton(icon: "square.and.arrow.up.fill", label: "Share") {
              ShareUtils.shareItem(item: permalink)
            }
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
