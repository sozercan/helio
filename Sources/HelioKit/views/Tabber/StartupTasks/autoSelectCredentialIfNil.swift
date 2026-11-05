//
//  autoSelectCredentialIfNil.swift
//  Helio
//
//  Created by Igor Marcossi on 08/12/23.
//

import Defaults
import Foundation

/// Selects the first signed-in account when none is selected, or the selected one is no longer saved.
@MainActor
func autoSelectCredentialIfNil(manager: RedditCredentialsManager = .shared) {
  if !manager.selectionIsSaved {
    let validCreds = manager.validCredentials
    if !validCreds.isEmpty {
      Defaults[.GeneralDefSettings].redditCredentialSelectedID = validCreds[0].id
    }
  }
}
