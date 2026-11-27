import Defaults
import Foundation

struct GeneralDefSettings: Equatable, Hashable, Codable, Defaults.Serializable {
  enum OnboardingState: String, Codable {
    case unknown, dismissed, active
  }

  var redditCredentialSelectedID: UUID? = nil
  var onboardingState: OnboardingState = .unknown
  var iCloudSyncUserDefaults = true
  var useAuth: Bool = false
  var showingUpsellDict: [String: Bool] = .init()
}
