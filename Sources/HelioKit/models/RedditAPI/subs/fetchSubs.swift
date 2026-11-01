//
//  fetchSubs.swift
//  Helio
//
//  Created by Igor Marcossi on 28/06/23.
//

import Alamofire
import CoreData
import Defaults
import Foundation
import os

func cleanSubs(_ subs: [ListingChild<SubredditData>]) -> [ListingChild<SubredditData>] {
  subs.compactMap { y in
    var x = y
    x.data?.description = ""
    x.data?.description_html = ""
    x.data?.public_description = ""
    x.data?.public_description_html = ""
    x.data?.submit_text_html = ""
    x.data?.submit_text = ""
    return x
  }
}

extension RedditAPI {
  /// `account`: whose subscriptions; the selected account when nil.
  func fetchAllSubs(after: String? = nil, accumulatedSubs: [ListingChild<SubredditData>]? = nil, account: RedditCredential? = nil) async -> [ListingChild<SubredditData>]? {
    // Base case: If 'after' is nil and some subs are already accumulated, simply return them.
    if let after, after.isEmpty, let accumulatedSubs {
      return accumulatedSubs
    }

    guard account != nil || Defaults[.GeneralDefSettings].redditCredentialSelectedID != nil else { return [] }

    let params = FetchSubsPayload(limit: 100, after: after)

    switch await self.doRequest("\(RedditAPI.redditApiURLBase)/subreddits/mine/subscriber.json", method: .get, params: params, paramsLocation: .queryString, decodable: Listing<SubredditData>.self, altCredential: account) {
    case let .success(data):
      // Same as a failed page: the sync would delete the subscriptions that were skipped.
      if let skipped = data.data?.skippedChildren, skipped > 0 {
        return nil
      }
      var newAccumulatedSubs = accumulatedSubs ?? []
      if let fetchedSubs = data.data?.children {
        newAccumulatedSubs += fetchedSubs.filter { $0.data?.subreddit_type != "user" }
      }

      if let dataAfter = data.data?.after, !dataAfter.isEmpty {
        // Recursive call with the new 'after' value and the updated accumulated subs.
        return await fetchAllSubs(after: dataAfter, accumulatedSubs: newAccumulatedSubs, account: account)
      } else {
        // All subs fetched, return the accumulated result
        return newAccumulatedSubs
      }
    case let .failure(error):
      Logger(subsystem: "com.sertacozercan.helio", category: "AccountListSync")
        .error("Failed to fetch subscriptions: \(error.localizedDescription)")
      // A partial list would make the sync drop every subscription on the pages that failed.
      return nil
    }
  }

  /// Whether the subscriptions were saved.
  @MainActor
  @discardableResult
  func updateSubsInCoreData(
    with subs: [ListingChild<SubredditData>],
    account: RedditCredential? = nil,
    credentialsManager: RedditCredentialsManager = .shared,
    context: NSManagedObjectContext? = nil,
  ) async -> Bool {
    guard let credential = account ?? credentialsManager.selectedCredential,
          let persistence = AccountListPersistence(account: credential, credentialsManager: credentialsManager, context: context)
    else { return false }
    return await persistence.replaceSubscriptions(with: subs.compactMap(\.data))
  }

  @discardableResult
  func fetchSubsAndSyncCoreData(account: RedditCredential? = nil) async -> Bool {
    let persistence = await MainActor.run {
      (account ?? RedditCredentialsManager.shared.selectedCredential).flatMap { AccountListPersistence(account: $0) }
    }
    guard let persistence else { return false }
    let snapshot = await persistence.captureSnapshot()
    guard let fetchedSubs = await fetchAllSubs(account: persistence.credential) else { return false }
    return await persistence.replaceSubscriptions(with: fetchedSubs.compactMap(\.data), snapshot: snapshot)
  }

  struct FetchSubsPayload: Codable {
    var limit: Int
    var after: String?
    //    var show = "all"
    var count = 0
    var raw_json = 1
  }
}
