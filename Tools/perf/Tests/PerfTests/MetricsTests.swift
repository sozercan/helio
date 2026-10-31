import Testing
@testable import perf

struct MetricsTests {
  @Test func categorizesRedditEndpoints() {
    let cases = [
      ("GET", "https://oauth.reddit.com/best.json?limit=25", "feed"),
      ("GET", "https://oauth.reddit.com/r/apple/hot.json", "feed"),
      ("GET", "https://oauth.reddit.com/r/apple/comments/abc.json?sort=top", "comments"),
      ("GET", "https://oauth.reddit.com/r/apple/about.json", "sub_about"),
      ("GET", "https://oauth.reddit.com/r/apple/about/rules.json", "sub_rules"),
      ("GET", "https://oauth.reddit.com/api/info?id=t3_a,t3_b", "info"),
      ("GET", "https://oauth.reddit.com/api/info?sr_name=apple", "info"),
      ("GET", "https://oauth.reddit.com/api/user_data_by_account_ids?ids=t2_a", "avatars"),
      ("POST", "https://www.reddit.com/api/v1/access_token", "token"),
      ("GET", "https://oauth.reddit.com/r/home/api/link_flair_v2", "flairs"),
      ("POST", "https://oauth.reddit.com/api/vote", "post_action"),
      ("GET", "https://fixture.local/img/p1.jpg", "image"),
      ("GET", "https://external-preview.redd.it/p1.jpg?auto=webp", "image"),
      ("GET", "https://www.theverge.com/article/1", "link_preview"),
      ("GET", "https://reddit.com/r/apple/comments/abc", "link_preview"),
      ("GET", "https://reddit.com/r/apple", "link_preview"),
      ("GET", "https://www.reddit.com/user/someone/about.json", "user"),
    ]
    for (method, url, expected) in cases {
      #expect(Metrics.category(method: method, url: url) == expected, "\(url)")
    }
  }

  @Test func measuresWindowsAndCountsRequestsUntilTheEnd() throws {
    let log = RunLog(text: """
    S 1000 start
    W 1700000000.000 wallclock
    M 0 cpu=100 main=50 fp=10 peak=20 hitch=0 hitches=0 frames=0
    P 100 home_open
    R 150 GET https://oauth.reddit.com/best.json
    R 160 GET https://fixture.local/img/p1.jpg
    P 200 scroll_start
    M 250 cpu=400 main=250 fp=11 peak=30 hitch=40 hitches=2 frames=10
    P 300 scroll_end
    P 350 post_open
    R 400 GET https://oauth.reddit.com/r/pics/comments/x.json
    R 410 GET https://www.example.com/article
    P 500 cscroll_end
    M 500 cpu=500 main=300 fp=12 peak=35 hitch=50 hitches=3 frames=20
    P 600 end
    R 700 GET https://oauth.reddit.com/api/info?id=t3_late
    """)
    let metrics = try #require(Metrics.metrics(of: log))
    #expect(metrics["feed_main_ms"] == 200)
    #expect(metrics["feed_hitches"] == 2)
    #expect(metrics["post_main_ms"] == 50)
    #expect(metrics["post_request_ms"] == 50)
    #expect(metrics["reddit_requests"] == 2)
    #expect(metrics["link_preview_requests"] == 1)
    #expect(metrics["requests.feed"] == 1)
    #expect(metrics["requests.info"] == nil)
    #expect(log.wallClock == 1_700_000_000)
  }

  @Test func ignoresRunsThatDidNotFinish() {
    #expect(Metrics.metrics(of: RunLog(text: "M 0 cpu=1 main=1\nP 100 home_open\n")) == nil)
  }

  @Test func ignoresRunsWhoseNavigationFailed() {
    #expect(Metrics.metrics(of: RunLog(text: "M 0 cpu=1 main=1\nP 100 home_open\nP 110 open_failed\nP 200 end\n")) == nil)
  }

  @Test func timesTheCommentsAPIRequestNotAPostPagePreview() throws {
    let log = RunLog(text: """
    M 0 cpu=1 main=1
    P 100 home_open
    P 200 post_open
    R 210 GET https://reddit.com/r/apple/comments/abc
    R 260 GET https://oauth.reddit.com/r/apple/comments/abc.json
    P 300 end
    """)
    #expect(try #require(Metrics.metrics(of: log))["post_request_ms"] == 60)
  }

  @Test func timesOnlyACommentsRequestBeforeTheEnd() throws {
    let log = RunLog(text: "M 0 cpu=1 main=1\nP 100 home_open\nP 200 post_open\nP 300 end\nR 400 GET https://oauth.reddit.com/r/a/comments/x.json\n")
    #expect(try #require(Metrics.metrics(of: log))["post_request_ms"] == -1)
  }

  @Test func flagsCountsOverBudgetAndUnlistedRequestKinds() {
    let rows = Metrics.budgetRows(median: ["reddit_requests": 5, "requests.feed": 3, "requests.token": 1, "feed_main_ms": 900],
                                  budget: ["reddit_requests": 6, "requests.feed": 2])
    #expect(rows.map(\.key) == ["reddit_requests", "requests.feed", "requests.token"])
    #expect(rows.filter(\.over).map(\.key) == ["requests.feed", "requests.token"])
    #expect(rows.filter(\.under).map(\.key) == ["reddit_requests"])
  }

  @Test func groupsBusySamplesIntoStalls() {
    let samples = [0, 1, 2, 3, 10, 11, 30].map { Profile.Sample(time: Double($0), frames: []) }
    #expect(Profile.busyRuns(samples).map(\.count) == [4, 2, 1])
  }

  @Test func seededRandomIsDeterministic() {
    var a = SeededRandom(state: 42), b = SeededRandom(state: 42)
    #expect((0 ..< 5).map { _ in a.int(0 ... 100) } == (0 ..< 5).map { _ in b.int(0 ... 100) })
  }
}
