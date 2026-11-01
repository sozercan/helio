//
//  autoSelectCredentialIfNil.swift
//  Helio
//
//  Created by Igor Marcossi on 08/12/23.
//

import Defaults
import Foundation

@MainActor
func autoSelectCredentialIfNil(_ selectedCredID: UUID? = Defaults[.GeneralDefSettings].redditCredentialSelectedID) {
  if selectedCredID == nil {
    let validCreds = RedditCredentialsManager.shared.validCredentials
    if !validCreds.isEmpty {
      Defaults[.GeneralDefSettings].redditCredentialSelectedID = validCreds[0].id
    }
  }
}
