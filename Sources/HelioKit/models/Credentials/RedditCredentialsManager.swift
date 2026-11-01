//
//  RedditCredentialsManager.swift
//  Helio
//
//  Created by Igor Marcossi on 19/11/23.
//

import Alamofire
import Combine
import Defaults
import Foundation
import KeychainAccess
import os
import SwiftUI
import Synchronization

@MainActor
@Observable
final class RedditCredentialsManager {
  static let shared = RedditCredentialsManager()
  static let profile = SelectedAccountProfile()
  @ObservationIgnored private var syncingAccounts: Set<RedditCredential.AuthorizationID> = []
  static func getById(_ credID: UUID) -> RedditCredential? {
    RedditCredentialsManager.shared.credentials.first(where: { $0.id == credID })
  }

  static let keychainEntryDivider = "\\--(*.*)--/"
  static let oldKeychainServiceString = "com.sertacozercan.helio.reddit-credentials"
  static let keychainServiceString = "com.sertacozercan.helio.reddit-multi-credentials"
  static let keychain = Keychain(service: RedditCredentialsManager.keychainServiceString).synchronizable(Defaults[.BehaviorDefSettings].iCloudSyncCredentials)
  private let persistence: Keychain?
  private let reloadSelectedProfile: @MainActor () -> Void
  @ObservationIgnored private let authorizations = Mutex<Set<RedditCredential.AuthorizationID>>([])
  private(set) var credentials: [RedditCredential] = []
  var validCredentials: [RedditCredential] {
    credentials.filter { $0.validationStatus == .authorized }
  }

  var selectedCredential: RedditCredential? {
    selectedCredential(id: Defaults[.GeneralDefSettings].redditCredentialSelectedID)
  }

  /// Reuse the installed selection/fallback while letting views observe the Defaults ID.
  func selectedCredential(id: UUID?) -> RedditCredential? {
    credentials.first { $0.id == id } ?? credentials.first
  }

  func syncCredentialsWithKeychain() {
    guard let persistence else { return }
    do {
      let allKeys = try persistence.allKeys()
      for keychainCredID in allKeys {
        if self.credentials.first(where: { $0.id.uuidString == keychainCredID }) == nil {
          try persistence.remove(keychainCredID)
        }
      }
      for cred in self.credentials {
        if let encoded = cred.toStr() {
          try persistence.set(encoded, key: cred.id.uuidString)
        }
      }
    } catch {
      Logger(subsystem: "com.sertacozercan.helio", category: "Credentials").error("Keychain sync failed: \(error.localizedDescription)")
    }
  }

  /// An in-memory store: no keychain, onboarding or account-list network side effects.
  /// The callback lets a local profile owner observe the same synchronous lifecycle boundary.
  init(credentials: [RedditCredential], reloadSelectedProfile: @escaping @MainActor () -> Void = {}) {
    persistence = nil
    self.reloadSelectedProfile = reloadSelectedProfile
    self.credentials = credentials
    authorizations.withLock { $0 = Set(credentials.compactMap(\.authorizationID)) }
  }

  nonisolated func containsAuthorization(_ authorization: RedditCredential.AuthorizationID) -> Bool {
    authorizations.withLock { $0.contains(authorization) }
  }

  /// Background persistence may commit while the grant remains installed. Grant
  /// invalidation uses this same lease; main-actor selection reads never take it.
  nonisolated func withCurrentAuthorization<Result>(_ authorization: RedditCredential.AuthorizationID, _ commit: () throws -> Result) rethrows -> Result? {
    try authorizations.withLock { current in
      guard current.contains(authorization) else { return nil }
      return try commit()
    }
  }

  private func publishCredentials(_ updated: [RedditCredential]) {
    let ids = Set(updated.compactMap(\.authorizationID))
    if ids != Set(credentials.compactMap(\.authorizationID)) {
      // Invalidate before publishing the replacement. An already leased commit
      // finishes before this mutation, never after a replacement account's write.
      authorizations.withLock { $0 = ids }
    }
    credentials = updated
  }

  func backfillUserName(_ name: String, for authorization: RedditCredential.AuthorizationID) {
    guard let index = credentials.firstIndex(where: { $0.id == authorization.credentialID }) else { return }
    var current = credentials[index]
    guard current.backfillUserName(name, for: authorization) else { return }
    var updated = credentials
    updated[index] = current
    publishCredentials(updated)
    syncCredentialsWithKeychain()
  }

  @discardableResult
  func markSubscriptionsSynced(for credential: RedditCredential, at date: Date = Date()) -> Bool {
    guard let authorization = credential.authorizationID, containsAuthorization(authorization) else { return false }
    let syncKey = "\(credential.id.uuidString)|\(credential.userName ?? "")"
    Defaults[.subsSyncedAt][syncKey] = date
    return true
  }

  init() {
    persistence = Self.keychain
    reloadSelectedProfile = { Self.profile.reload() }
    let okc = Keychain(service: Self.oldKeychainServiceString)
    let kc = Self.keychain

    let oldApiAppID = okc["apiAppID"]
    let oldApiAppSecret = okc["apiAppSecret"]
    let oldRefreshToken = okc["refreshToken"]

    var importedCredential: RedditCredential? = nil
    if oldApiAppID != nil || oldApiAppSecret != nil || oldRefreshToken != nil {
      importedCredential = .init(apiAppID: oldApiAppID ?? "", apiAppSecret: oldApiAppSecret ?? "", refreshToken: oldRefreshToken)
    }

    if let importedCredential {
      credentials.append(importedCredential)
      Defaults[.GeneralDefSettings].redditCredentialSelectedID = importedCredential.id
    }

    try? okc.remove("apiAppID")
    try? okc.remove("apiAppSecret")
    try? okc.remove("refreshToken")
    try? okc.remove("accessToken")

    let keychainKeys = kc.allKeys()

    for key in keychainKeys {
      if let credStr = kc[key], let decodedCred = credStr.toObj(RedditCredential.self) {
        credentials.append(decodedCred)
      }
    }

    authorizations.withLock { $0 = Set(credentials.compactMap(\.authorizationID)) }
  }

  /// Launch and account switches sync subscriptions and multis at most this often. Subscribing
  /// in the app updates the local copy, and pulling the subreddit list syncs right away.
  static let subsSyncInterval: TimeInterval = 60 * 60

  func updateMe() {
    reloadSelectedProfile()
    guard persistence != nil, let credential = selectedCredential, let authorization = credential.authorizationID else { return }
    // A credential signed in to another account is synced again.
    let syncKey = "\(credential.id.uuidString)|\(credential.userName ?? "")"
    if let syncedAt = Defaults[.subsSyncedAt][syncKey], Date().timeIntervalSince(syncedAt) < Self.subsSyncInterval {
      return
    }
    guard syncingAccounts.insert(authorization).inserted else { return }
    Task(priority: .utility) {
      defer { self.syncingAccounts.remove(authorization) }
      // As this account: the selection can change before the task runs.
      async let subsSynced = RedditAPI.shared.fetchSubsAndSyncCoreData(account: credential)
      async let multisSynced = RedditAPI.shared.fetchMyMultis(account: credential)
      if await subsSynced, await multisSynced {
        self.markSubscriptionsSynced(for: credential)
      }
    }
  }

  /// Mutations and their persistence/profile effects finish in the same main-actor turn.
  func saveCred(_ cred: RedditCredential, forceCreate: Bool = true) {
    let index = credentials.firstIndex { $0.id == cred.id }
    guard index != nil || forceCreate else { return }
    let previousAuthorization = selectedCredential?.authorizationID
    if persistence != nil, Defaults[.GeneralDefSettings].onboardingState != .dismissed {
      Defaults[.GeneralDefSettings].onboardingState = .dismissed
      Nav.shared.presentingSheetsQueue = Nav.shared.presentingSheetsQueue.filter { $0 != .onboarding }
    }
    var updated = credentials
    if let index {
      updated[index] = cred
    } else {
      updated.append(cred)
    }
    publishCredentials(updated)
    // Auto-select if no credential is currently selected.
    if Defaults[.GeneralDefSettings].redditCredentialSelectedID == nil {
      Defaults[.GeneralDefSettings].redditCredentialSelectedID = cred.id
    }
    syncCredentialsWithKeychain()
    if previousAuthorization != selectedCredential?.authorizationID {
      updateMe()
    }
  }

  /// Main's conditional edit/renewal API shares the synchronous mutation owner.
  func updateCred(_ id: UUID, _ change: (inout RedditCredential) -> Bool) {
    guard let index = credentials.firstIndex(where: { $0.id == id }) else { return }
    var current = credentials[index]
    guard change(&current), current != credentials[index] else { return }
    let previousAuthorization = selectedCredential?.authorizationID
    var updated = credentials
    updated[index] = current
    publishCredentials(updated)
    syncCredentialsWithKeychain()
    if previousAuthorization != selectedCredential?.authorizationID {
      updateMe()
    }
  }

  /// Untouched web-session edits keep the current rotated cookies, token and grant.
  func saveDraft(_ draft: RedditCredential, openedAs original: RedditCredential) {
    var draft = draft
    if let authorization = original.authorizationID,
       draft.authorizationID == authorization,
       let current = credentials.first(where: { $0.id == draft.id }),
       current.authorizationID == authorization,
       draft.userName == original.userName
    {
      // /me may have backfilled a migrated record while this editor was open.
      draft.userName = current.userName
    }
    if let current = credentials.first(where: { $0.id == draft.id }),
       current.isWebSession, draft.isWebSession, draft.webSessionCookies == original.webSessionCookies
    {
      draft.webSessionCookies = current.webSessionCookies
      draft.accessToken = current.accessToken
      draft.webSessionID = current.webSessionID
    }
    saveCred(draft, forceCreate: true)
  }

  func updateWebAccessToken(_ token: RedditCredential.AccessToken?, cookies: String?, renewedFrom: String, for authorization: RedditCredential.AuthorizationID) {
    guard let index = credentials.firstIndex(where: { $0.id == authorization.credentialID }) else { return }
    var current = credentials[index]
    guard current.updateWebAccessToken(token, cookies: cookies, renewedFrom: renewedFrom, for: authorization), current != credentials[index] else { return }
    var updated = credentials
    updated[index] = current
    publishCredentials(updated)
    syncCredentialsWithKeychain()
    if token == nil, selectedCredential?.id == authorization.credentialID {
      reloadSelectedProfile()
    }
  }

  /// A refresh only updates the authorization that requested it, preserving newer edits.
  func updateAccessToken(_ token: RedditCredential.AccessToken?, for authorization: RedditCredential.AuthorizationID) {
    guard let index = credentials.firstIndex(where: { $0.id == authorization.credentialID }) else { return }
    var current = credentials[index]
    guard current.updateAccessToken(token, for: authorization), current != credentials[index] else { return }
    var updated = credentials
    updated[index] = current
    publishCredentials(updated)
    syncCredentialsWithKeychain()
    if token == nil, selectedCredential?.id == authorization.credentialID {
      reloadSelectedProfile()
    }
  }

  func deleteCred(_ cred: RedditCredential) {
    let previousAuthorization = selectedCredential?.authorizationID
    withAnimation {
      publishCredentials(credentials.filter { $0.id != cred.id })
    }
    syncCredentialsWithKeychain()
    if previousAuthorization != selectedCredential?.authorizationID {
      updateMe()
    }
  }

  func wipeAllCredentials() {
    withAnimation { publishCredentials([]) }
    reloadSelectedProfile()
    guard let persistence else { return }
    do {
      try persistence.removeAll()
    } catch {
      Logger(subsystem: "com.sertacozercan.helio", category: "Credentials").error("Keychain wipe failed: \(error.localizedDescription)")
    }
  }
}
