import XCTest

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
    let deadline = Date().addingTimeInterval(15)
    while Date() < deadline {
      if app.buttons["Continue"].exists, app.buttons["Continue"].isHittable {
        app.buttons["Continue"].tap()
      } else if app.buttons["xmark.circle.fill"].firstMatch.exists, app.buttons["xmark.circle.fill"].firstMatch.isHittable {
        app.buttons["xmark.circle.fill"].firstMatch.tap()
        let confirm = app.alerts.buttons["Yes"]
        if confirm.waitForExistence(timeout: 2) {
          confirm.tap()
        }
      } else if home.exists, home.isHittable {
        break
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    XCTAssertTrue(home.waitForExistence(timeout: 10))
    let firstSubreddit = app.staticTexts["apple"].firstMatch
    XCTAssertTrue(firstSubreddit.waitForExistence(timeout: 15))
    app.terminate()
  }
}
