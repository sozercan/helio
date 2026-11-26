import Defaults
import Foundation

@MainActor
func autoSelectCredentialIfNil(manager: RedditCredentialsManager = .shared) {
  if !manager.selectionIsSaved {
    let validCreds = manager.validCredentials
    if !validCreds.isEmpty {
      Defaults[.GeneralDefSettings].redditCredentialSelectedID = validCreds[0].id
    }
  }
}
