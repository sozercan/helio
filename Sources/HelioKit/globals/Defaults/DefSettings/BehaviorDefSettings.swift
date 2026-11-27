import Defaults

struct BehaviorDefSettings: Equatable, Hashable, Codable, Defaults.Serializable {
  var openYoutubeApp: Bool = false
  var enableSwipeAnywhere: Bool = false
  var preferenceDefaultFeed: String = "subList"
  var doLiveText: Bool = true
  var iCloudSyncCredentials: Bool = true
  var restoreReadingSession: Bool = false

  enum CodingKeys: String, CodingKey {
    case openYoutubeApp
    case enableSwipeAnywhere
    case preferenceDefaultFeed
    case doLiveText
    case iCloudSyncCredentials
    case restoreReadingSession
  }

  init(
    openYoutubeApp: Bool = false,
    enableSwipeAnywhere: Bool = false,
    preferenceDefaultFeed: String = "subList",
    doLiveText: Bool = true,
    iCloudSyncCredentials: Bool = true,
    restoreReadingSession: Bool = false,
  ) {
    self.openYoutubeApp = openYoutubeApp
    self.enableSwipeAnywhere = enableSwipeAnywhere
    self.preferenceDefaultFeed = preferenceDefaultFeed
    self.doLiveText = doLiveText
    self.iCloudSyncCredentials = iCloudSyncCredentials
    self.restoreReadingSession = restoreReadingSession
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    openYoutubeApp = try container.decodeIfPresent(Bool.self, forKey: .openYoutubeApp) ?? false
    enableSwipeAnywhere = try container.decodeIfPresent(Bool.self, forKey: .enableSwipeAnywhere) ?? false
    preferenceDefaultFeed = try container.decodeIfPresent(String.self, forKey: .preferenceDefaultFeed) ?? "subList"
    doLiveText = try container.decodeIfPresent(Bool.self, forKey: .doLiveText) ?? true
    iCloudSyncCredentials = try container.decodeIfPresent(Bool.self, forKey: .iCloudSyncCredentials) ?? true
    restoreReadingSession = try container.decodeIfPresent(Bool.self, forKey: .restoreReadingSession) ?? false
  }
}
