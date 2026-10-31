import XCTest

/// First launch for `Tools/perf/perf.py`: a fresh install on fixture data, taken through
/// onboarding and What's New, so the benchmark then launches as a returning user. Skipped unless
/// the perf tool passes its network shim.
final class PerfSetupUITests: XCTestCase {
  func testSetup() throws {
    let env = ProcessInfo.processInfo.environment
    guard let shim = env["HELIO_PERF_SHIM"], let fixtures = env["HELIO_PERF_FIXTURES"] else {
      throw XCTSkip("Run by Tools/perf/perf.py")
    }
    let app = XCUIApplication()
    app.launchEnvironment["DYLD_INSERT_LIBRARIES"] = shim
    app.launchEnvironment["PERF_FIXTURES"] = fixtures
    app.launchEnvironment["PERF_SEED_CREDENTIAL"] = "1"
    app.launchEnvironment["PERF_LOG"] = env["HELIO_PERF_LOG"]
    app.launch()

    let home = app.staticTexts["Home"].firstMatch
    for _ in 0 ..< 10 {
      if app.buttons["Continue"].exists {
        app.buttons["Continue"].tap()
      } else if app.buttons["xmark.circle.fill"].firstMatch.exists {
        app.buttons["xmark.circle.fill"].firstMatch.tap()
        let confirm = app.alerts.buttons["Yes"]
        if confirm.waitForExistence(timeout: 2) {
          confirm.tap()
        }
      } else if home.exists, home.isHittable {
        break
      }
      sleep(1)
    }
    XCTAssertTrue(home.waitForExistence(timeout: 10))
    // Let the launch requests (token, account, subscriptions) land before quitting.
    sleep(5)
    app.terminate()
  }
}
