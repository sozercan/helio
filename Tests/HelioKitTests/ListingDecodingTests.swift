import Foundation
import Testing
@testable import HelioKit

struct ListingDecodingTests {
  /// The sample post as a JSON object, with `changes` applied.
  private func postJSON(_ changes: [String: Any]) throws -> [String: Any] {
    var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(postSampleData)) as? [String: Any])
    json.merge(changes) { _, new in new }
    return json
  }

  private func listing(children: [[String: Any]]) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
      "kind": "Listing",
      "data": ["after": "t3_next", "dist": children.count, "children": children.map { ["kind": "t3", "data": $0] }],
    ])
  }

  @Test func skipsAPostThatFailsToDecodeAndKeepsTheRest() throws {
    let data = try listing(children: [
      postJSON(["id": "a"]),
      postJSON(["id": "b", "ups": "not a number"]),
      postJSON(["id": "c"]),
    ])

    let decoded = try JSONDecoder().decode(Listing<PostData>.self, from: data)

    #expect(decoded.data?.children?.compactMap(\.data?.id) == ["a", "c"])
    #expect(decoded.data?.after == "t3_next")
    #expect(decoded.data?.dist == 3)
  }

  @Test func aListingOfAnotherTypeStillFailsSoEitherFallsBack() throws {
    // The comments endpoint returns [post listing, comment listing], decoded by trying posts first.
    let comment = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(getCommentSampleData(false))) as? [String: Any])
    let response = try JSONSerialization.data(withJSONObject: [
      ["kind": "Listing", "data": ["children": [["kind": "t3", "data": postJSON(["id": "p"])]]]],
      ["kind": "Listing", "data": ["children": [["kind": "t1", "data": comment]]]],
    ])

    let decoded = try JSONDecoder().decode(RedditAPI.FetchPostCommentsResponse.self, from: response)

    guard decoded.count == 2, case let .first(posts) = decoded[0], case let .second(comments) = decoded[1] else {
      Issue.record("Expected a post listing then a comment listing, got \(decoded)")
      return
    }
    #expect(posts.data?.children?.compactMap(\.data?.id) == ["p"])
    #expect(comments.data?.children?.compactMap(\.data?.id) == ["helioSample"])
  }

  @Test func stillEncodesAndDecodesRoundTrip() throws {
    let data = try listing(children: [postJSON(["id": "a"])])
    let decoded = try JSONDecoder().decode(Listing<PostData>.self, from: data)

    let roundTripped = try JSONDecoder().decode(Listing<PostData>.self, from: JSONEncoder().encode(decoded))

    #expect(roundTripped == decoded)
  }
}
