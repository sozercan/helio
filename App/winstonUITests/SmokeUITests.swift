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
    // closeSheetBtn's xmark.circle.fill symbol is exposed as "Close".
    let close = app.buttons.matching(NSPredicate(format: "label ==[c] 'close' OR label CONTAINS 'xmark'")).firstMatch
    if close.waitForExistence(timeout: 5) {
      close.tap()
      let confirm = app.alerts.buttons["Yes"]
      if confirm.waitForExistence(timeout: 3) { confirm.tap() }
    }
    let whatsNew = app.buttons["Continue"]
    if whatsNew.waitForExistence(timeout: 3) { whatsNew.tap() }
  }

  /// Taps the tab's icon center like a finger would. XCUITest's element tap on iOS 26 tab bar
  /// items lands left of the icon, on the app's tab overlay slot for the previous tab.
  private func openTab(_ name: String) {
    let tab = app.tabBars.buttons[name]
    XCTAssertTrue(tab.waitForExistence(timeout: 5), "\(name) tab missing")
    app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: tab.frame.midX, dy: tab.frame.midY)).tap()
  }

  private func screenshot(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  func testGeneralSettingsShowReadHistoryActions() {
    openTab("Settings")
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    let general = app.staticTexts["General"].firstMatch
    XCTAssertTrue(general.waitForExistence(timeout: 5))
    general.tap()

    XCTAssertTrue(app.staticTexts["Import Apollo read history"].waitForExistence(timeout: 5))
    let clear = app.staticTexts["Clear read history"]
    if !clear.exists { app.swipeUp() }
    XCTAssertTrue(clear.waitForExistence(timeout: 5))
    screenshot("general-settings")
    clear.tap()
    XCTAssertTrue(app.alerts["Clear read history?"].waitForExistence(timeout: 5))
    app.alerts.buttons["Cancel"].tap()

    openTab("Posts")
    XCTAssertTrue(app.tabBars.buttons["Posts"].isSelected)
  }
}
