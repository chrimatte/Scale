import XCTest

final class ScaleUITests: XCTestCase {
    func testHomeAndSettings() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Start weigh-in"].waitForExistence(timeout: 10))
        capture("Home")
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.textFields["Athlete ID"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save and verify"].isEnabled)
        capture("Settings")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Start weigh-in"].waitForExistence(timeout: 5))

    }
    func testOptionalSharing() {
        let app = XCUIApplication()
        app.launchArguments = ["--preview-weigh-in"]
        app.launch()
        let question = app.alerts["Vuoi condividere il peso su Intervals?"]
        XCTAssertTrue(question.waitForExistence(timeout: 10))
        capture("Share confirmation")
        question.buttons["Non ora"].tap()
        XCTAssertTrue(app.staticTexts["Weigh-in complete"].exists)
        let share = app.buttons["Share with Intervals.icu"]
        if !share.isHittable { app.swipeUp() }
        share.tap()
        XCTAssertTrue(question.waitForExistence(timeout: 3))
        question.buttons["Condividi"].tap()
        XCTAssertTrue(app.staticTexts["Weight shared"].waitForExistence(timeout: 5))
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
