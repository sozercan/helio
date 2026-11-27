import SwiftUI

struct FilteredSubredditsSettings: View {
  private let userCollections = UserCollectionsStore.shared
  @State private var newSubreddit = ""
  @State private var addSubredditAlert = false
  @Environment(\.useTheme) private var theme

  private func removeSubreddit(at index: Int) {
    userCollections.removeFilteredSubreddit(at: index)
  }

  var body: some View {
    let filteredSubreddits = userCollections.filteredSubreddits
    List {
      Section {
        ForEach(Array(filteredSubreddits.enumerated()), id: \.element) { index, subreddit in
          Text(subreddit)
            .swipeActions {
              Button(action: {
                withAnimation {
                  removeSubreddit(at: index)
                }

              }) {
                Image(systemName: "hand.raised.slash.fill")
              }
              .tint(Color.green)
            }
        }
      }
      .themedListSection()
    }
    .themedListBG(theme.lists.bg)
    .navigationTitle("Filtered Subreddits")
    .navigationBarItems(trailing:
      HStack {
        Button(action: {
          addSubredditAlert = true
        }) {
          Image(systemName: "plus")
        }
      })
    .navigationViewStyle(StackNavigationViewStyle())
    .alert("Enter a subreddit", isPresented: $addSubredditAlert) {
      TextField("Meow", text: $newSubreddit)
      Button("OK", action: {
        if !newSubreddit.isEmpty, !filteredSubreddits.contains(newSubreddit) {
          withAnimation {
            userCollections.addFilteredSubreddit(newSubreddit)
          }

          newSubreddit = ""
        }
      })
      Button("Cancel", action: {})
    } message: {
      Text("Enter a subreddit you wish to filter (case-sensitive).")
    }
  }
}
