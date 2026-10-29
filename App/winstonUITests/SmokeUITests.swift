import XCTest

/// Exercises navigation and settings that work without Reddit credentials.
final class SmokeUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launch()
    dismissOnboarding()
  }

  /// First launch shows onboarding and then a "What's new" sheet over the tab bar.
  private func dismissOnboarding() {
    let close = app.buttons["xmark.circle.fill"].firstMatch
    if close.waitForExistence(timeout: 5) {
      // A tap while the sheet is still animating in can be lost, so retry until it lands.
      let confirm = app.alerts.buttons["Yes"]
      for _ in 0..<3 where !confirm.exists {
        close.tap()
        _ = confirm.waitForExistence(timeout: 3)
      }
      if confirm.exists { confirm.tap() }
    }
    let whatsNew = app.buttons["Continue"]
    if whatsNew.waitForExistence(timeout: 3) { whatsNew.tap() }
  }

  /// Taps the tab's icon center like a finger would. XCUITest's element tap on iOS 26 tab bar
  /// items lands left of the icon, on the app's tab overlay slot for the previous tab.
  /// iPhone has a bottom tab bar; iPad's top tab bar isn't exposed as a tab bar.
  private func tabButton(_ name: String) -> XCUIElement {
    app.tabBars.buttons[name].exists ? app.tabBars.buttons[name] : app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
  }

  private func openTab(_ name: String) {
    let tab = tabButton(name)
    XCTAssertTrue(tab.waitForExistence(timeout: 5), "\(name) tab missing")
    // Relative to the tab itself, so it also lands when the interface is rotated (unfolded iPhone Duo).
    tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
  }

  /// Lists only expose rows that are on screen, so scroll until `element` appears.
  @discardableResult
  private func scrollTo(_ element: XCUIElement, attempts: Int = 4) -> Bool {
    for _ in 0..<attempts where !element.waitForExistence(timeout: 2) {
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

  /// On iPad (and an unfolded iPhone Duo) the window is wide and can change width while the
  /// app runs; rotating exercises that path.
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
