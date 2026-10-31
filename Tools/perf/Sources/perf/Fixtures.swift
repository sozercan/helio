import Foundation

/// The fake Reddit data the shim serves. Four Home pages of 25 posts (images, external links,
/// links to other Reddit posts and subreddits, crossposts, galleries, videos, YouTube, self posts
/// with Markdown), a ~160-comment thread per post, subreddit about pages, subscriptions, inbox and
/// multis. Authors repeat across posts and comments like on Reddit. Seeded, so every run gets the
/// same data. Images are made by the shim; there's no media.
enum Fixtures {
  /// Bump when the data changes, so existing fixture directories are regenerated.
  static let version = 1

  static func ensure() -> URL {
    let dir = Paths.work.appendingPathComponent("fixtures")
    let stamp = dir.appendingPathComponent(".version")
    if (try? String(contentsOf: stamp, encoding: .utf8)) != "\(version)" {
      try? FileManager.default.removeItem(at: dir)
      do {
        var generator = Generator()
        try generator.write(to: dir)
        try "\(version)".write(to: stamp, atomically: true, encoding: .utf8)
      } catch {
        fail("can't write fixtures: \(error)")
      }
    }
    return dir
  }
}

/// SplitMix64: a small seeded generator, so fixtures are the same on every machine.
struct SeededRandom {
  var state: UInt64

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  mutating func int(_ range: ClosedRange<Int>) -> Int {
    range.lowerBound + Int(next() % UInt64(range.count))
  }

  mutating func chance(_ probability: Double) -> Bool {
    Double(next() % 1_000_000) / 1_000_000 < probability
  }

  mutating func pick<T>(_ items: [T]) -> T {
    items[Int(next() % UInt64(items.count))]
  }
}

private struct Generator {
  typealias JSON = [String: Any]

  var random = SeededRandom(state: 42)
  let now = Int(Date().timeIntervalSince1970)
  let image = "https://fixture.local/img/"
  let sizes = [1: (1200, 675), 2: (1200, 1200), 3: (1200, 900), 4: (1200, 1200), 5: (900, 1200), 6: (1200, 1200), 7: (600, 2000)]
  let subs = ["apple", "pics", "EarthPorn", "iOSProgramming", "technology", "AskReddit", "Wallpapers", "apolloapp",
              "NatureIsFuckingLit", "itookapicture", "oddlysatisfying", "videos", "swift", "worldnews", "science",
              "gaming", "movies", "todayilearned", "space", "dataisbeautiful"]
  let authors = (0 ..< 45).map { String(format: "author_%02d", $0) }
  let commenters = (0 ..< 140).map { String(format: "commenter_%03d", $0) }
  let domains = ["apple.com", "theverge.com", "arstechnica.com", "nytimes.com", "bbc.co.uk", "github.com", "wired.com", "techcrunch.com"]
  let vocabulary = ("the quick brown fox jumps over lazy dog swift reddit apollo client fixture performance scroll "
    + "layout render image video comment thread markdown link preview cache batch request token").split(separator: " ").map(String.init)
  /// Post kinds by position in a page of 25.
  let pattern = ["self", "image", "link", "image", "self", "crosspost", "image", "link", "self", "gallery", "image", "redditlink",
                 "self", "image", "link", "video", "image", "self", "youtube", "image", "link", "self", "image", "sublink", "image"]

  mutating func words(_ count: Int) -> String {
    (0 ..< count).map { _ in random.pick(vocabulary) }.joined(separator: " ")
  }

  func markdownHTML(_ text: String) -> String {
    let escaped = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    return "<!-- SC_OFF --><div class=\"md\"><p>\(escaped)</p>\n</div><!-- SC_ON -->"
  }

  func preview(_ n: Int, external: Bool = false) -> JSON {
    let (width, height) = sizes[n]!
    let url = external ? "https://external-preview.redd.it/p\(n).jpg?auto=webp" : "\(image)p\(n).jpg"
    let source: JSON = ["url": url, "width": width, "height": height]
    return ["images": [["id": "img\(n)", "source": source, "resolutions": external ? [] : [source], "variants": JSON()]], "enabled": true]
  }

  func basePost(id: String, sub: String, title: String, author: String, ageHours: Int, score: Int, comments: Int) -> JSON {
    [
      "id": id, "name": "t3_\(id)", "title": title, "subreddit": sub, "subreddit_id": "t5_\(sub.lowercased())",
      "subreddit_name_prefixed": "r/\(sub)", "author": author, "author_fullname": "t2_\(author.lowercased())",
      "created_utc": now - ageHours * 3600, "created": now - ageHours * 3600, "score": score, "ups": score, "downs": 0,
      "upvote_ratio": 0.94, "num_comments": comments, "permalink": "/r/\(sub)/comments/\(id)/fixture/",
      "likes": NSNull(), "saved": false, "hidden": false, "clicked": false, "visited": false, "archived": false,
      "locked": false, "stickied": false, "over_18": false, "spoiler": false, "gilded": 0, "all_awardings": [Any](),
      "total_awards_received": 0, "distinguished": NSNull(), "edited": false, "is_video": false,
      "link_flair_text": NSNull(), "link_flair_type": "text", "link_flair_richtext": [Any](),
      "link_flair_background_color": "", "link_flair_text_color": "dark", "author_flair_text": NSNull(),
      "subreddit_type": "public", "num_crossposts": 0, "media": NSNull(), "secure_media": NSNull(),
      "suggested_sort": NSNull(), "hide_score": false, "quarantine": false, "allow_live_comments": false,
      "is_robot_indexable": true, "contest_mode": false, "subreddit_subscribers": 4_200_000, "send_replies": true,
      "can_gild": false, "removed_by_category": NSNull(), "approved_by": NSNull(),
    ]
  }

  mutating func post(_ i: Int, kind: String, id override: String? = nil) -> JSON {
    let id = override ?? String(format: "pf%04d", i)
    let sub = subs[i % subs.count]
    // The first three posts have fixed scores, so they're easy to find in the UI.
    let score = i < 3 ? [1300, 2400, 3500][i] : random.int(5 ... 40000)
    var d = basePost(id: id, sub: sub, title: "Post \(i): \(words(random.int(6 ... 18)))", author: authors[(i * 7) % authors.count],
                     ageHours: 1 + i % 23, score: score, comments: random.int(0 ... 3000))
    if i % 9 == 2 {
      d["link_flair_text"] = random.pick(["Discussion", "News", "Question", "OC"])
      if i % 2 == 1 {
        d["link_flair_background_color"] = "#ff4500"
      }
    }
    let plain: JSON = ["is_self": false, "selftext": "", "selftext_html": NSNull()]
    switch kind {
    case "self":
      let text = words(random.int(20 ... 120)) + "\n\n**bold** and [a link](https://example.com) " + words(10)
      d.merge(["is_self": true, "domain": "self.\(sub)", "url": "https://www.reddit.com\(d["permalink"]!)", "selftext": text,
               "selftext_html": markdownHTML(text), "thumbnail": "self", "post_hint": "self"]) { $1 }
    case "image":
      let n = 1 + i % 7
      d.merge(plain) { $1 }
      d.merge(["domain": "i.redd.it", "url": "\(image)p\(n).jpg", "thumbnail": "\(image)t\(n).jpg", "thumbnail_width": 140,
               "thumbnail_height": 140, "post_hint": "image", "preview": preview(n)]) { $1 }
    case "link":
      let domain = domains[i % domains.count], n = 1 + i % 6
      d.merge(plain) { $1 }
      d.merge(["domain": domain, "url": "https://www.\(domain)/article/\(i)", "thumbnail": "\(image)t\(n).jpg", "post_hint": "link",
               "preview": preview(n, external: true)]) { $1 }
    case "redditlink":
      d.merge(plain) { $1 }
      d.merge(["domain": "reddit.com", "url": "https://www.reddit.com/r/\(sub)/comments/\(String(format: "pf%04d", (i + 3) % 100))/fixture/",
               "thumbnail": "default", "post_hint": "link"]) { $1 }
    case "sublink":
      d.merge(plain) { $1 }
      d.merge(["domain": "reddit.com", "url": "https://www.reddit.com/r/\(subs[(i + 5) % subs.count])/", "thumbnail": "default",
               "post_hint": "link"]) { $1 }
    case "gallery":
      let keys = ["p3", "p6", "p4"]
      var metadata = JSON()
      for key in keys {
        let (x, y) = sizes[Int(key.dropFirst())!]!
        metadata[key] = ["status": "valid", "e": "Image", "m": "image/jpg", "id": key, "s": ["x": x, "y": y, "u": "\(image)\(key).jpg"]] as JSON
      }
      d.merge(plain) { $1 }
      d.merge(["domain": "reddit.com", "url": "https://www.reddit.com/gallery/\(id)", "thumbnail": "\(image)t3.jpg", "post_hint": NSNull(),
               "is_gallery": true, "gallery_data": ["items": keys.enumerated().map { ["media_id": $1, "id": $0] }],
               "media_metadata": metadata]) { $1 }
    case "video":
      d.merge(plain) { $1 }
      d.merge(["domain": "v.redd.it", "url": "https://v.redd.it/video\(i)", "thumbnail": "\(image)t1.jpg", "is_video": true,
               "post_hint": "hosted:video", "preview": preview(1),
               "media": ["reddit_video": ["fallback_url": "https://fixture.local/video/DASH_720.mp4", "hls_url": NSNull(),
                                          "width": 828, "height": 582, "duration": 20, "is_gif": false]]]) { $1 }
    case "youtube":
      d.merge(plain) { $1 }
      d.merge(["domain": "youtube.com", "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "thumbnail": "default",
               "post_hint": "rich:video", "media": ["type": "youtube.com", "oembed": [
                 "html": "<iframe width=\"356\" height=\"200\" src=\"https://www.youtube.com/embed/dQw4w9WgXcQ?feature=oembed\"></iframe>",
                 "thumbnail_url": "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg", "width": 356, "height": 200,
                 "author_name": "Video Author", "author_url": "https://www.youtube.com/@fixture", "type": "video",
               ]]]) { $1 }
    default:
      break
    }
    return d
  }

  mutating func comment(_ id: String, post: String, sub: String, depth: Int, parent: String, replies: [JSON]?) -> JSON {
    let text = words(random.int(5 ... 60)), score = random.int(1 ... 5000)
    let author = random.pick(commenters)
    let data: JSON = [
      "id": id, "name": "t1_\(id)", "body": text, "body_html": markdownHTML(text), "author": author,
      "author_fullname": "t2_\(author)", "score": score, "ups": score, "downs": 0,
      "created_utc": now - random.int(1 ... 20) * 3600, "created": now - 3600, "depth": depth,
      "parent_id": parent, "link_id": "t3_\(post)", "subreddit": sub, "subreddit_id": "t5_\(sub.lowercased())",
      "permalink": "/r/\(sub)/comments/\(post)/fixture/\(id)/", "likes": NSNull(), "saved": false, "edited": false,
      "gilded": 0, "all_awardings": [Any](), "stickied": false, "is_submitter": false, "distinguished": NSNull(),
      "collapsed": false, "score_hidden": false, "controversiality": 0, "author_flair_text": NSNull(),
      "send_replies": true, "archived": false, "locked": false, "can_gild": false,
      "replies": replies.map { ["kind": "Listing", "data": ["children": $0, "after": NSNull(), "before": NSNull()]] as Any } ?? "",
    ]
    return ["kind": "t1", "data": data]
  }

  mutating func thread(for post: JSON) -> [JSON] {
    let id = post["id"] as! String, sub = post["subreddit"] as! String
    var count = 0
    func build(_ depth: Int, parent: String, budget: Int) -> [JSON] {
      var kids: [JSON] = []
      let n = depth == 0 ? 30 : random.int(1 ... 4)
      for _ in 0 ..< n where count < budget {
        count += 1
        let cid = "\(id)c\(count)"
        let replies = depth < 5 && random.chance(0.55) ? build(depth + 1, parent: "t1_\(cid)", budget: budget) : nil
        kids.append(comment(cid, post: id, sub: sub, depth: depth, parent: parent, replies: replies))
      }
      if depth == 1, random.chance(0.15) {
        let more = "\(id)m\(count)"
        kids.append(["kind": "more", "data": ["count": 3, "name": "t1_\(more)", "id": more, "parent_id": parent, "depth": depth,
                                              "children": ["\(more)a", "\(more)b", "\(more)c"]]])
      }
      return kids
    }
    var roots = build(0, parent: "t3_\(id)", budget: 160)
    // A known first comment, so tests can tell the comments loaded.
    var first = roots[0]["data"] as! JSON
    first["body"] = "Top comment for \(id)"
    first["body_html"] = markdownHTML("Top comment for \(id)")
    roots[0]["data"] = first
    let more = "\(id)mroot"
    roots.append(["kind": "more", "data": ["count": 40, "name": "t1_\(more)", "id": more, "parent_id": "t3_\(id)", "depth": 0,
                                           "children": (0 ..< 40).map { "\(more)\($0)" }]])
    return roots
  }

  func listing(_ children: [Any], after: String? = nil) -> JSON {
    ["kind": "Listing", "data": ["children": children, "after": after ?? NSNull(), "before": NSNull(), "dist": children.count, "modhash": ""] as JSON]
  }

  mutating func subreddit(_ name: String) -> JSON {
    ["kind": "t5", "data": [
      "id": name.lowercased(), "name": "t5_\(name.lowercased())", "display_name": name, "display_name_prefixed": "r/\(name)",
      "title": "\(name) title", "url": "/r/\(name)/", "public_description": words(12), "description": words(80),
      "subscribers": random.int(1000 ... 40_000_000), "user_is_subscriber": true, "user_has_favorited": false,
      "over18": false, "subreddit_type": "public", "icon_img": "", "community_icon": "",
      "key_color": "#ff4500", "primary_color": "#0079d3", "created_utc": 1_200_000_000,
    ] as JSON]
  }

  mutating func write(to dir: URL) throws {
    let fm = FileManager.default
    for sub in ["things", "comments", "about"] {
      try fm.createDirectory(at: dir.appendingPathComponent(sub), withIntermediateDirectories: true)
    }
    func save(_ object: Any, _ path: String) throws {
      try JSONSerialization.data(withJSONObject: object).write(to: dir.appendingPathComponent(path))
    }

    var posts: [JSON] = []
    for i in 0 ..< 100 {
      if pattern[i % 25] == "crosspost" {
        let parent = post(i + 1000, kind: "image", id: String(format: "xp%04d", i))
        var d = post(i, kind: "self")
        d.merge(["is_self": false, "domain": "self.\(parent["subreddit"]!)", "url": parent["permalink"]!, "selftext": "",
                 "selftext_html": NSNull(), "post_hint": NSNull(), "crosspost_parent": parent["name"]!, "crosspost_parent_list": [parent]]) { $1 }
        posts.append(d)
      } else {
        posts.append(post(i, kind: pattern[i % 25]))
      }
    }
    for page in 0 ..< 4 {
      let chunk = Array(posts[page * 25 ..< (page + 1) * 25])
      let after = page < 3 ? "t3_\(chunk.last!["id"]!)" : nil
      let key = page == 0 ? "first" : "t3_\(posts[page * 25 - 1]["id"]!)"
      try save(listing(chunk.map { ["kind": "t3", "data": $0] }, after: after), "feed_\(key).json")
    }
    for p in posts {
      let id = p["id"] as! String
      try save(["kind": "t3", "data": p], "things/t3_\(id).json")
      for parent in p["crosspost_parent_list"] as? [JSON] ?? [] {
        try save(["kind": "t3", "data": parent], "things/t3_\(parent["id"]!).json")
      }
      try save([listing([["kind": "t3", "data": p]]), listing(thread(for: p))], "comments/\(id).json")
    }
    let root = posts[0]
    try save(["json": ["errors": [Any](), "data": ["things": (0 ..< 20).map {
      comment("more\($0)", post: root["id"] as! String, sub: root["subreddit"] as! String, depth: 1, parent: "t3_\(root["id"]!)", replies: nil)
    }]]], "morechildren.json")
    for sub in subs {
      try save(subreddit(sub), "about/\(sub.lowercased()).json")
    }
    try save(listing((subs + (0 ..< 25).map { "extra_sub_\($0)" }).map { subreddit($0) }), "subs_mine.json")
    try save([Any](), "multis.json")
    try save(listing((0 ..< 10).map { k in ["kind": "t4", "data": [
      "id": "msg\(k)", "name": "t4_msg\(k)", "author": random.pick(authors), "author_fullname": "t2_x", "subject": "comment reply",
      "body": words(20), "body_html": markdownHTML(words(20)), "new": k < 2, "type": "comment_reply", "was_comment": true,
      "created": now - 3600 * k, "created_utc": now - 3600 * k, "context": "/r/apple/comments/pf0000/fixture/pf0000c1/",
      "subreddit": "apple", "subreddit_name_prefixed": "r/apple", "dest": "fixture_user", "link_title": "a post",
    ] as JSON] }), "inbox.json")
    try save(listing([]), "empty_listing.json")
    try save(["json": ["errors": [Any]()]], "ok.json")
    try save(["access_token": "fixture-token", "token_type": "bearer", "expires_in": 3600, "scope": "*"], "token.json")
    try save(["name": "fixture_user", "id": "fx1", "icon_img": "", "snoovatar_img": "", "created": 1_500_000_000,
              "created_utc": 1_500_000_000, "link_karma": 1234, "comment_karma": 5678, "total_karma": 6912, "awardee_karma": 0,
              "awarder_karma": 0, "verified": true, "is_gold": false, "is_mod": false, "has_verified_email": true, "inbox_count": 0,
              "subreddit": ["display_name": "u_fixture_user", "title": "", "icon_img": "", "banner_img": "", "public_description": "",
                            "subscribers": 0, "name": "t5_fx", "url": "/user/fixture_user/", "user_is_banned": false, "over_18": false]],
             "me.json")
    try Data("""
    <html><head><meta property="og:title" content="Fixture article"/>\
    <meta property="og:description" content="An article description for the link preview."/>\
    <meta property="og:image" content="https://fixture.local/img/t2.jpg"/>\
    <meta property="og:url" content="https://example.com/article"/></head><body>hi</body></html>
    """.utf8).write(to: dir.appendingPathComponent("og.html"))
  }
}
