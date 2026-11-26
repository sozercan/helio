import Defaults
import Foundation

@MainActor
func checkForOnboardingStatus() {
  var open = false
  open = switch Defaults[.GeneralDefSettings].onboardingState {
  case .active: true
  case .unknown: RedditCredentialsManager.shared.credentials.isEmpty
  case .dismissed: false
  }
  if open {
    Nav.present(.onboarding)
  }
}
