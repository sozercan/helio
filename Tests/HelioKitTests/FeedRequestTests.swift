import Alamofire
import Foundation
import Synchronization
import Testing
@testable import HelioKit

/// Only the injected session uses this protocol; no fixture request reaches the network.
private class FeedRequestProtocol: URLProtocol, @unchecked Sendable {
  static let requests = Mutex<[URLRequest]>([])

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    Self.requests.withLock { $0.append(request) }
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(#"{"kind":"Listing","data":{"children":[],"after":null}}"#.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Suite(.serialized)
struct FeedRequestTests {
  private func account(_ name: String?) -> RedditCredential {
    RedditCredential(apiAppID: "placeholder-client-id", accessToken: "placeholder-\(name ?? "unknown")-access-token", refreshToken: "placeholder-grant", expiration: 3600, lastRefresh: Date(), userName: name)
  }

  private func session() -> Session {
    FeedRequestProtocol.requests.withLock { $0 = [] }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FeedRequestProtocol.self]
    return Session(configuration: configuration)
  }

  @Test(arguments: [false, true]) func savedUsesOneAccountForItsURLAndAuthorization(legacyFetch: Bool) async throws {
    let first = account("placeholder_first")
    let second = account("placeholder_second")
    let reads = Mutex(0)
    let api = RedditAPI(session: session(), currentAccount: {
      let count = reads.withLock { $0 += 1
        return $0
      }
      return count == 1 ? first : second
    })
    if legacyFetch {
      let result = await api.fetchSavedPosts(savedKeyword)
      #expect(result != nil)
    } else {
      let result = await api.fetchSubPosts(savedKeyword, limit: 15)
      #expect(result != nil)
    }
    let requests = FeedRequestProtocol.requests.withLock { $0 }
    let request = try #require(requests.first)
    #expect(requests.count == 1)
    let expectedPath = legacyFetch ? "/user/placeholder_first/saved" : "/user/placeholder_first/saved/best.json"
    #expect(request.url?.path == expectedPath)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer placeholder-placeholder_first-access-token")
    let accountReads = reads.withLock { $0 }
    #expect(accountReads == 1)
  }

  @Test(arguments: [nil, ""] as [String?]) func savedWithoutAUsernameFailsWithoutRequestingHome(name: String?) async {
    let credential = account(name)
    let api = RedditAPI(session: session(), currentAccount: { credential })
    let feed = await api.fetchSubPosts(savedKeyword)
    let saved = await api.fetchSavedPosts(savedKeyword)
    #expect(feed == nil)
    #expect(saved == nil)
    let requests = FeedRequestProtocol.requests.withLock { $0 }
    #expect(requests.isEmpty)
  }

  @MainActor
  @Test func aMigratedAccountCanLoadSavedAfterItsProfileBackfillsTheName() async throws {
    let credential = account(nil)
    let manager = RedditCredentialsManager(credentials: [credential])
    let data = try JSONDecoder().decode(UserData.self, from: Data(#"{"id":"placeholder_migrated","name":"placeholder_migrated"}"#.utf8))
    let profile = SelectedAccountProfile(currentAccount: { manager.selectedCredential }, fetch: { _ in data }, persistUserName: { manager.backfillUserName($0, for: $1) })
    await profile.refresh()
    let api = RedditAPI(session: session(), currentAccount: { await manager.selectedCredential })
    let result = await api.fetchSubPosts(savedKeyword)
    #expect(result != nil)
    let requests = FeedRequestProtocol.requests.withLock { $0 }
    let request = try #require(requests.first)
    #expect(request.url?.path == "/user/placeholder_migrated/saved/best.json")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer placeholder-unknown-access-token")
    #expect(manager.selectedCredential?.authorizationID == credential.authorizationID)
  }

  @Test func everyFeedEndpointUsesItsExplicitLimit() async throws {
    let credential = account(nil)
    let api = RedditAPI(session: session(), currentAccount: { credential })
    _ = await api.fetchSubPosts("", limit: 15)
    _ = await api.fetchMultiPosts(path: "/user/placeholder/m/example", limit: 15)
    _ = await api.fetchUserOverview("placeholder", limit: 15)
    _ = await api.searchInSubreddit("example", RedditAPI.AdvancedPostsSearch(subreddit: "example", flairs: nil, sortOption: .best, limit: 15))
    let requests = FeedRequestProtocol.requests.withLock { $0 }
    #expect(requests.count == 4)
    for request in requests {
      let url = try #require(request.url)
      let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
      #expect(query?.first(where: { $0.name == "limit" })?.value == "15")
    }
    #expect(requests.first?.url?.path == "/best.json")
  }
}

extension FeedRequestTests {
  @MainActor
  @Test func anAccountSwitchAndBackDuringDispatchCannotFetchAnotherAccountsSavedItems() async throws {
    let first = account("placeholder_first")
    let second = account("placeholder_second")
    var selected = first
    let reads = Mutex(0)
    let api = RedditAPI(session: session(), currentAccount: {
      reads.withLock { $0 += 1 }
      return second
    })
    let manager = FeedItemsManager<SubListingSortOption>(sorting: .best, currentCredential: { selected }, fetchFn: { after, sorting, _, _, context in
      selected = second
      // Endpoint dispatch crosses an actor boundary while B is selected. Restoring
      // A before publishing is not enough: the HTTP request itself must use A.
      let result = await api.fetchSubPosts(savedKeyword, limit: context.limit, sort: sorting ?? .best, after: after, altCredential: context.credential)
      selected = first
      guard let result else { return nil }
      return ([], result.1)
    })
    await manager.reload()
    let requests = FeedRequestProtocol.requests.withLock { $0 }
    let request = try #require(requests.first)
    #expect(requests.count == 1)
    #expect(request.url?.path == "/user/placeholder_first/saved/best.json")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer placeholder-placeholder_first-access-token")
    #expect(reads.withLock { $0 } == 0)
    #expect(manager.displayMode == .empty)
  }

  @Test func everyFeedEndpointHonorsTheCapturedCredentialWithoutReadingSelection() async {
    let first = account("placeholder_first")
    let second = account("placeholder_second")
    let reads = Mutex(0)
    let api = RedditAPI(session: session(), currentAccount: {
      reads.withLock { $0 += 1 }
      return second
    })
    _ = await api.fetchSubPosts("", limit: 15, altCredential: first)
    _ = await api.fetchMultiPosts(path: "/user/placeholder_first/m/example", limit: 15, altCredential: first)
    _ = await api.fetchUserOverview("placeholder_first", limit: 15, altCredential: first)
    _ = await api.fetchInbox(limit: 15, altCredential: first)
    _ = await api.searchInSubreddit("example", RedditAPI.AdvancedPostsSearch(subreddit: "example", flairs: nil, sortOption: .best, limit: 15), altCredential: first)
    let requests = FeedRequestProtocol.requests.withLock { $0 }
    #expect(requests.count == 5)
    for request in requests {
      #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer placeholder-placeholder_first-access-token")
    }
    #expect(reads.withLock { $0 } == 0)
  }
}

/// A multi sort and the listing it should request.
struct MultiSortCase: Sendable {
  let sort: SubListingSortOption
  let path: String
  var range: String?
}

extension FeedRequestTests {
  @Test(arguments: [
    MultiSortCase(sort: .best, path: "/user/placeholder/m/example.json"),
    MultiSortCase(sort: .hot, path: "/user/placeholder/m/example/hot.json"),
    MultiSortCase(sort: .new, path: "/user/placeholder/m/example/new.json"),
    MultiSortCase(sort: .controversial, path: "/user/placeholder/m/example/controversial.json"),
    MultiSortCase(sort: .top(.week), path: "/user/placeholder/m/example/top.json", range: "week"),
  ])
  func multiFeedsRequestTheChosenSort(_ sortCase: MultiSortCase) async throws {
    let credential = account("placeholder")
    let api = RedditAPI(session: session(), currentAccount: { credential })
    for multiPath in ["/user/placeholder/m/example", "/user/placeholder/m/example/"] {
      FeedRequestProtocol.requests.withLock { $0 = [] }
      _ = await api.fetchMultiPosts(path: multiPath, sort: sortCase.sort, limit: 15, altCredential: credential)
      let request = try #require(FeedRequestProtocol.requests.withLock { $0 }.first)
      let url = try #require(request.url)
      let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
      #expect(url.path == sortCase.path)
      #expect(query?.first(where: { $0.name == "t" })?.value == sortCase.range)
      #expect(query?.first(where: { $0.name == "limit" })?.value == "15")
    }
  }
}
