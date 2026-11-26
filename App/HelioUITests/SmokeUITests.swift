import XCTest

final class SmokeUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launch()
    dismissOnboarding()
  }

  private func dismissOnboarding() {
    let close = app.buttons["xmark.circle.fill"].firstMatch
    if close.waitForExistence(timeout: 5) {
      let hittable = NSPredicate(format: "exists == true AND hittable == true")
      let expectation = XCTNSPredicateExpectation(predicate: hittable, object: close)
      if XCTWaiter.wait(for: [expectation], timeout: 5) == .completed {
        close.tap()
      }
      let confirm = app.alerts.buttons["Yes"]
      if confirm.waitForExistence(timeout: 5) {
        confirm.tap()
      }
    }
    let whatsNew = app.buttons["Continue"]
    if whatsNew.waitForExistence(timeout: 3) {
      whatsNew.tap()
    }
  }

  private func tabButton(_ name: String) -> XCUIElement {
    app.tabBars.buttons[name].exists ? app.tabBars.buttons[name] : app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
  }

  private func openTab(_ name: String) {
    let tab = tabButton(name)
    XCTAssertTrue(tab.waitForExistence(timeout: 5), "\(name) tab missing")
    tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
  }

  @discardableResult
  private func scrollTo(_ element: XCUIElement, attempts: Int = 4) -> Bool {
    for _ in 0 ..< attempts where !element.waitForExistence(timeout: 2) {
      app.swipeUp()
    }
    return element.exists
  }

  private func screenshot(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  func testGeneralSettingsShowReadHistoryActions() {
    openTab("Settings")
    let general = app.staticTexts["General"].firstMatch
    XCTAssertTrue(general.waitForExistence(timeout: 5))
    general.tap()

    XCTAssertTrue(scrollTo(app.staticTexts["Import Apollo read history"]))
    let clear = app.staticTexts["Clear read history"]
    XCTAssertTrue(scrollTo(clear))
    screenshot("general-settings")
    clear.tap()
    XCTAssertTrue(app.alerts["Clear read history?"].waitForExistence(timeout: 5))
    app.alerts.buttons["Cancel"].tap()

    openTab("Posts")
    XCTAssertTrue(tabButton("Posts").isSelected)
  }

  func testWideLayoutSurvivesRotation() throws {
    guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("Needs a wide window") }
    openTab("Settings")
    XCTAssertTrue(app.staticTexts["General"].firstMatch.waitForExistence(timeout: 5))
    screenshot("wide-portrait")
    XCUIDevice.shared.orientation = .landscapeLeft
    XCTAssertTrue(app.staticTexts["General"].firstMatch.waitForExistence(timeout: 5))
    screenshot("wide-landscape")
    app.staticTexts["General"].firstMatch.tap()
    XCTAssertTrue(scrollTo(app.staticTexts["Import Apollo read history"]))
    screenshot("wide-landscape-general")
    XCUIDevice.shared.orientation = .portrait
  }
}
