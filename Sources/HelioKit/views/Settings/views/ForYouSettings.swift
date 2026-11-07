//
//  ForYouSettings.swift
//  Helio
//

import Defaults
import SwiftUI

/// Why For You suggests what it does: the signals it found for the selected account, the
/// subreddits it picked and passed over, and how the last page's suggestions were narrowed
/// down. All of it was worked out on the device.
struct ForYouSettings: View {
  @Default(.forYouDismissedSubs) private var dismissed
  /// Observed for the selected account's id: switching accounts changes only that.
  @Default(.GeneralDefSettings) private var generalDefSettings
  @Environment(\.useTheme) private var theme
  @State private var diagnostics: ForYouDiagnostics?
  @State private var loaded = false

  /// The signed-in account, whose diagnostics show: another account's never do.
  private var account: ForYouEngine.Account? {
    RedditCredentialsManager.shared.selectedCredential(id: generalDefSettings.redditCredentialSelectedID).map(ForYouEngine.Account.init)
  }

  private func load() async {
    let account = account
    guard let account else {
      diagnostics = nil
      loaded = true
      return
    }
    let loadedDiagnostics = await ForYouEngine.shared.diagnostics(account: account)
    // The account may have changed while this loaded.
    guard self.account == account else { return }
    diagnostics = loadedDiagnostics
    loaded = true
  }

  var body: some View {
    List {
      if let diagnostics {
        signals(diagnostics)
        candidates("Suggested subreddits", diagnostics.candidates, footer: "Posts from these are mixed into For You. Swipe to stop suggesting one.", dismissable: true)
        if let page = diagnostics.lastPage {
          lastPage(page)
        }
        if !diagnostics.unqualified.isEmpty {
          candidates("Not enough signal", diagnostics.unqualified,
                     footer: "One stray upvote or save isn't enough: a subreddit needs a few recent ones, or to be listed as related by one you follow.", dismissable: false)
        }
      } else if loaded {
        Section {
          Text("Open For You to work out suggestions, then come back here to see why they were picked.")
            .foregroundStyle(.secondary)
        }
        .themedListSection()
      }

      if !dismissed.isEmpty {
        Section {
          ForEach(dismissed, id: \.self) { subreddit in
            Text("r/\(subreddit)")
              .swipeActions {
                Button("Suggest Again", systemImage: "arrow.uturn.backward") {
                  withAnimation { ForYouFeed.undismiss(subreddit) }
                }
                .tint(.green)
              }
          }
        } header: {
          Text("Not interested")
        } footer: {
          Text("Swipe to let For You suggest one again.")
        }
        .themedListSection()
      }

      Section {
        Button("Work Out Suggestions Again") {
          Task {
            await ForYouEngine.shared.invalidate()
            diagnostics = nil
          }
        }
      } footer: {
        Text("Suggestions are worked out again the next time For You loads, and every few hours.")
      }
      .themedListSection()
    }
    .themedListBG(theme.lists.bg)
    .navigationTitle("For You")
    .task(id: account) {
      diagnostics = nil
      loaded = false
      await load()
    }
    .refreshable { await load() }
  }

  private func signals(_ diagnostics: ForYouDiagnostics) -> some View {
    Section {
      LabeledContent("Worked out", value: diagnostics.builtAt.formatted(.relative(presentation: .named)))
      LabeledContent("Upvoted posts", value: diagnostics.upvotedCount.map(String.init) ?? "Couldn't load")
      LabeledContent("Saved posts and comments", value: diagnostics.savedCount.map(String.init) ?? "Couldn't load")
      LabeledContent("Related communities", value: relatedSummary(diagnostics))
      LabeledContent("Interest matching", value: diagnostics.likedTitles.map { "\($0) titles" } ?? "Unavailable")
    } header: {
      Text("Signals")
    } footer: {
      Text("Related communities come from the sidebars of subreddits you follow. Interest matching compares post titles with ones you upvoted and saved, on this device.")
    }
    .themedListSection()
  }

  private func relatedSummary(_ diagnostics: ForYouDiagnostics) -> String {
    let seeds = diagnostics.seeds.count
    guard seeds > 0 else { return "None looked up" }
    let failed = diagnostics.relatedFailures
    return failed == 0 ? "\(seeds) subreddits looked up" : "\(seeds - failed) of \(seeds) loaded"
  }

  private func candidates(_ title: String, _ candidates: [ForYouCandidate], footer: String, dismissable: Bool) -> some View {
    Section {
      if candidates.isEmpty {
        Text("None").foregroundStyle(.secondary)
      }
      ForEach(candidates, id: \.name) { candidate in
        VStack(alignment: .leading, spacing: 2) {
          Text("r/\(candidate.name)")
          Text(candidate.breakdown.summary)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .swipeActions {
          if dismissable {
            Button("Not Interested", systemImage: "hand.thumbsdown") {
              ForYouFeed.dismiss(candidate.name)
              withAnimation { diagnostics = diagnostics.map { removing(candidate.name, from: $0) } }
            }
            .tint(.red)
          }
        }
      }
    } header: {
      Text(title)
    } footer: {
      Text(footer)
    }
    .themedListSection()
  }

  private func removing(_ name: String, from diagnostics: ForYouDiagnostics) -> ForYouDiagnostics {
    ForYouDiagnostics(builtAt: diagnostics.builtAt, seeds: diagnostics.seeds, relatedFailures: diagnostics.relatedFailures,
                      upvotedCount: diagnostics.upvotedCount, savedCount: diagnostics.savedCount, likedTitles: diagnostics.likedTitles,
                      candidates: diagnostics.candidates.filter { $0.name != name }, unqualified: diagnostics.unqualified, lastPage: diagnostics.lastPage)
  }

  private func lastPage(_ page: ForYouPageStats) -> some View {
    Section {
      LabeledContent("Posts from suggested subreddits", value: "\(page.fetched)")
      LabeledContent("After filters", value: "\(page.eligible)")
      LabeledContent("Relevant enough", value: page.threshold == nil ? "Not checked" : "\(page.relevant)")
      LabeledContent("Shown", value: "\(page.shown)")
    } header: {
      Text("Last page")
    } footer: {
      Text("Filters leave out NSFW, pinned and filtered posts. A suggestion is relevant enough when its title is at least as close to your interests as a typical post in your Home.")
    }
    .themedListSection()
  }
}
