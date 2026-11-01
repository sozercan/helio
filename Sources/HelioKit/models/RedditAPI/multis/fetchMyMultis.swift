//
//  fetchMyMultis.swift
//  Helio
//
//  Created by Igor Marcossi on 20/08/23.
//

import Alamofire
@preconcurrency import CoreData
import Foundation
import os

extension RedditAPI {
  /// `account`: whose multis; the selected account when nil.
  func fetchMyMultis(account: RedditCredential? = nil) async -> Bool {
    let persistence = await MainActor.run {
      (account ?? RedditCredentialsManager.shared.selectedCredential).flatMap { AccountListPersistence(account: $0) }
    }
    guard let persistence else { return false }
    let snapshot = await persistence.captureSnapshot()

    let params = FetchMyMultisPayload()

    switch await self.doRequest("\(RedditAPI.redditApiURLBase)/api/multi/mine", method: .get, params: params, paramsLocation: .queryString, decodable: [MultiContainerResponse].self, altCredential: persistence.credential) {
    case let .success(data):
      return await persistence.replaceMultis(with: data.compactMap(\.data), snapshot: snapshot)
    case let .failure(error):
      Logger(subsystem: "com.sertacozercan.helio", category: "AccountListSync")
        .error("Failed to fetch multis: \(error.localizedDescription)")
      return false
    }
  }

  @MainActor
  func updateMultisInCoreData(
    with data: [MultiContainerResponse],
    account: RedditCredential,
    credentialsManager: RedditCredentialsManager = .shared,
    context: NSManagedObjectContext? = nil,
  ) async -> Bool {
    guard let persistence = AccountListPersistence(account: account, credentialsManager: credentialsManager, context: context) else { return false }
    return await persistence.replaceMultis(with: data.compactMap(\.data))
  }

  struct FetchMyMultisPayload: Codable {
    var expand_srs = true
    var raw_json = 1
  }

  struct MultiContainerResponse: Codable {
    let kind: String?
    var data: MultiData?
  }
}
