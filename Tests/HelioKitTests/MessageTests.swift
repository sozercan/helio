import Foundation
import Testing
@testable import HelioKit

struct MessageTests {
  private func decode(_ json: String) throws -> MessageData {
    try JSONDecoder().decode(MessageData.self, from: Data(json.utf8))
  }

  @Test func readsThePostIdFromAPermalink() {
    #expect(getPostId(from: "/r/apple/comments/abc123/a_title/def456/?context=3") == "abc123")
    #expect(getPostId(from: "https://www.reddit.com/r/apple/comments/abc123/") == "abc123")
  }

  @Test func rejectsLinksWithoutAPostId() {
    #expect(getPostId(from: "") == nil)
    #expect(getPostId(from: "/r/apple") == nil)
    #expect(getPostId(from: "/r/apple/comments/") == nil)
    #expect(getPostId(from: "/message/messages/xyz") == nil)
  }

  @Test func commentRepliesOpenTheirPost() throws {
    let data = try decode("""
    {"id": "r1", "name": "t1_r1", "author": "someone", "subreddit": "apple", "parent_id": "t1_c1",
     "type": "comment_reply", "was_comment": true, "context": "/r/apple/comments/abc123/t/r1/?context=3"}
    """)
    guard case let .reddit(.postHighlighted(post, highlight)) = data.commentDestination else {
      Issue.record("expected a highlighted post")
      return
    }
    #expect(post.id == "abc123")
    #expect(highlight == "t1_c1")
  }

  @Test func postRepliesHighlightTheReply() throws {
    let data = try decode("""
    {"id": "r2", "name": "t1_r2", "author": "someone", "subreddit": "apple", "parent_id": "t3_abc123",
     "type": "post_reply", "was_comment": true, "context": "/r/apple/comments/abc123/t/r2/?context=3"}
    """)
    guard case let .reddit(.postHighlighted(_, highlight)) = data.commentDestination else {
      Issue.record("expected a highlighted post")
      return
    }
    #expect(highlight == "t1_r2")
  }

  @Test func privateMessagesHaveNoPost() throws {
    // Private messages come with an empty context and no subreddit or parent.
    let data = try decode("""
    {"id": "pm1", "name": "t4_pm1", "author": "someone", "subject": "Hi", "body": "Hello",
     "subreddit": null, "parent_id": null, "context": "", "type": "unknown", "was_comment": false}
    """)
    #expect(data.commentDestination == nil)
  }

  @Test func repliesWithAnUnreadableLinkHaveNoPost() throws {
    let data = try decode("""
    {"id": "r3", "name": "t1_r3", "subreddit": "apple", "context": "/r/apple"}
    """)
    #expect(data.commentDestination == nil)
  }
}
