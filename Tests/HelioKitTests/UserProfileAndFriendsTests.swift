import Alamofire
import Foundation
import Synchronization
import Testing
@testable import HelioKit

private class UserProfileRequestProtocol: URLProtocol, @unchecked Sendable {
  struct RecordedRequest {
    let url: URL?
    let method: String?
    let body: Data?
    let contentType: String?
    let authorization: String?
  }

  static let requests = Mutex<[RecordedRequest]>([])
  static let responseBody = Mutex<Data>(Data(#"{"kind":"Listing","data":{"children":[],"after":null}}"#.utf8))
  static let statusCode = Mutex<Int>(200)

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let bodyData: Data? = if let httpBody = request.httpBody {
      httpBody
    } else if let stream = request.httpBodyStream {
      Self.readStream(stream)
    } else {
      nil
    }
    Self.requests.withLock {
      $0.append(RecordedRequest(
        url: request.url,
        method: request.httpMethod,
        body: bodyData,
        contentType: request.value(forHTTPHeaderField: "Content-Type"),
        authorization: request.value(forHTTPHeaderField: "Authorization"),
      ))
    }
    let code = Self.statusCode.withLock { $0 }
    let body = Self.responseBody.withLock { $0 }
    let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  private static func readStream(_ stream: InputStream) -> Data {
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let read = stream.read(&buffer, maxLength: buffer.count)
      if read > 0 {
        data.append(buffer, count: read)
      } else {
        break
      }
    }
    return data
  }
}

@Suite(.serialized)
struct UserProfileAndFriendsTests {
  private func account(_ name: String) -> RedditCredential {
    RedditCredential(
      apiAppID: "placeholder-client-id",
      accessToken: "placeholder-\(name)-token",
      refreshToken: "placeholder-refresh-token",
      expiration: 3600,
      lastRefresh: Date(),
      userName: name,
    )
  }

  private func makeAPI(
    credential: RedditCredential,
    response: String = #"{"kind":"Listing","data":{"children":[],"after":null}}"#,
    statusCode: Int = 200,
  ) -> RedditAPI {
    UserProfileRequestProtocol.requests.withLock { $0 = [] }
    UserProfileRequestProtocol.responseBody.withLock { $0 = Data(response.utf8) }
    UserProfileRequestProtocol.statusCode.withLock { $0 = statusCode }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [UserProfileRequestProtocol.self]
    return RedditAPI(session: Session(configuration: configuration), currentAccount: { credential })
  }

  @Test(arguments: UserListingSection.allCases)
  func fetchUserOverviewTargetsEachSectionEndpoint(section: UserListingSection) async throws {
    let api = makeAPI(credential: account("placeholder_me"))
    let result = await api.fetchUserOverview("placeholder_me", section: section, "t3_after", limit: 20)
    #expect(result != nil)
    let request = try #require(UserProfileRequestProtocol.requests.withLock { $0.first })
    #expect(request.url?.path == "/user/placeholder_me/\(section.endpointSegment).json")
    let query = try URLComponents(url: #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
    #expect(query?.first(where: { $0.name == "limit" })?.value == "20")
    #expect(query?.first(where: { $0.name == "after" })?.value == "t3_after")
    #expect(request.authorization == "Bearer placeholder-placeholder_me-token")
  }

  @Test func ownSectionsIncludePrivateFeedsAndPublicSectionsExcludeThem() {
    #expect(UserListingSection.publicSections == [.overview, .submitted, .comments])
    #expect(UserListingSection.ownSections == [.overview, .submitted, .comments, .upvoted, .downvoted, .saved, .hidden])
    #expect(UserListingSection.upvoted.isPrivate)
    #expect(UserListingSection.downvoted.isPrivate)
    #expect(UserListingSection.saved.isPrivate)
    #expect(UserListingSection.hidden.isPrivate)
    #expect(!UserListingSection.overview.isPrivate)
  }

  @Test func fetchFriendsDecodesUserListResponse() async throws {
    let payload = #"{"kind":"UserList","data":{"children":[{"id":"t2_abc","name":"placeholder_friend","date":1700000000,"rel_id":"r9_1","note":"met on reddit"}]}}"#
    let api = makeAPI(credential: account("placeholder_me"), response: payload)
    let friends = try #require(await api.fetchFriends())
    #expect(friends.count == 1)
    #expect(friends[0].id == "t2_abc")
    #expect(friends[0].name == "placeholder_friend")
    #expect(friends[0].date == 1_700_000_000)
    #expect(friends[0].note == "met on reddit")
    let request = try #require(UserProfileRequestProtocol.requests.withLock { $0.first })
    #expect(request.method == "GET")
    #expect(request.url?.path == "/api/v1/me/friends")
  }

  @Test func setFriendSendsPutJSONToAddAndDeleteToRemove() async throws {
    let api = makeAPI(credential: account("placeholder_me"), response: #"{"name":"placeholder_target","id":"t2_xyz"}"#)
    let added = await api.setFriend("placeholder_target", isFriend: true)
    #expect(added)
    let removed = await api.setFriend("placeholder_target", isFriend: false)
    #expect(removed)

    let requests = UserProfileRequestProtocol.requests.withLock { $0 }
    #expect(requests.count == 2)
    #expect(requests[0].method == "PUT")
    #expect(requests[0].url?.path == "/api/v1/me/friends/placeholder_target")
    #expect(requests[0].contentType?.contains("application/json") == true)
    let body = try #require(requests[0].body)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
    #expect(json["name"] == "placeholder_target")

    #expect(requests[1].method == "DELETE")
    #expect(requests[1].url?.path == "/api/v1/me/friends/placeholder_target")
  }

  @MainActor
  @Test func friendsListModelLoadsSortsAndRemovesFriends() async {
    let cred = account("placeholder_me")
    let model = FriendsListModel(
      currentAccount: { cred },
      fetchFriends: { _ in
        [
          RedditFriend(id: "t2_2", name: "zeta_user", date: 1_700_000_000, rel_id: nil, note: nil),
          RedditFriend(id: "t2_1", name: "alpha_user", date: 1_700_000_100, rel_id: nil, note: nil),
        ]
      },
      removeFriendRequest: { name, _ in name == "alpha_user" },
    )
    await model.load()
    #expect(model.state == .loaded)
    #expect(model.friends.map(\.name) == ["alpha_user", "zeta_user"])

    let removed = await model.remove(model.friends[0])
    #expect(removed)
    #expect(model.friends.map(\.name) == ["zeta_user"])
  }

  @MainActor
  @Test func friendsListModelIgnoresStaleLoadAfterAccountSwitch() async {
    var active = account("placeholder_first")
    let model = FriendsListModel(
      currentAccount: { active },
      fetchFriends: { cred in
        if cred?.userName == "placeholder_first" {
          try? await Task.sleep(for: .milliseconds(50))
          return [RedditFriend(id: "t2_old", name: "old_friend", date: nil, rel_id: nil, note: nil)]
        }
        return [RedditFriend(id: "t2_new", name: "new_friend", date: nil, rel_id: nil, note: nil)]
      },
    )
    let firstTask = Task { await model.load() }
    try? await Task.sleep(for: .milliseconds(10))
    active = account("placeholder_second")
    await model.load(clearExisting: true)
    await firstTask.value
    #expect(model.state == .loaded)
    #expect(model.friends.map(\.name) == ["new_friend"])
  }
}
