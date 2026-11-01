import XCTest

final class CrashUITests: XCTestCase {
    func testCreateNetworkAndPlace() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["ROOMS_API_BASE"] = "http://localhost:8792/api/"
        app.launch()
        // Each run uses an isolated local development database, never the production API.
        if app.tabBars.buttons["Networks"].waitForExistence(timeout:3) {
            app.tabBars.buttons["Networks"].tap()
            app.buttons["Settings"].tap()
            app.buttons["Sign out"].tap()
        }
        XCTAssertTrue(app.textFields["Your name"].waitForExistence(timeout:10))
        app.textFields["Your name"].tap(); app.textFields["Your name"].typeText("Simulator Tester")
        app.textFields["Email"].tap(); app.textFields["Email"].typeText("ui-\(UUID().uuidString.prefix(8))@example.invalid")
        let pw = app.secureTextFields["Password (10+ characters)"]
        pw.tap(); pw.typeText("test-password-123")
        app.swipeUp()
        app.buttons["Make yourself at home"].tap()
        XCTAssertTrue(app.buttons["I’ve saved my key"].waitForExistence(timeout:20))
        app.buttons["I’ve saved my key"].tap()
        app.tabBars.buttons["Networks"].tap()
        let name = app.textFields["Family, friends, chosen family…"]
        XCTAssertTrue(name.waitForExistence(timeout:10))
        name.tap(); name.typeText("Simulator Network")
        app.buttons["Create & get a code"].tap()
        XCTAssertTrue(app.buttons["Share network code"].waitForExistence(timeout:15))
        app.tabBars.buttons["My places"].tap()
        app.buttons["Add a place"].tap()
        let title = app.textFields["A name for your place"]
        XCTAssertTrue(title.waitForExistence(timeout:5))
        title.tap(); title.typeText("Test guest room")
        let fields = [("Street name (no door number)","Example Street"),("Town / city","Test City"),("Postcode / ZIP code","TEST"),("Country","Test Country")]
        for (label,value) in fields {
            let field = app.textFields[label]
            if !field.isHittable { app.swipeUp() }
            field.tap(); field.typeText(value)
        }
        app.swipeUp()
        let save = app.buttons["Add this place"]
        XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(app.staticTexts["Test guest room"].waitForExistence(timeout:15))
        app.tabBars.buttons["Explore"].tap()
        XCTAssertTrue(app.staticTexts["Places to reconnect"].waitForExistence(timeout:10))
        let screenshot = XCTAttachment(screenshot:app.screenshot()); screenshot.name = "Explore"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(app.navigationBars["A world of welcome"].exists)
    }
}
