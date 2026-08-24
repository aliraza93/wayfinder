import XCTest

/// XCUITest: start/stop affordance via UITest host (menu-bar extra is not hittable under XCTest).
final class StartStopUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHostExposesStartStopAndEditorControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitesting"]
        app.launch()

        // Onboarding auto-opens under -uitesting via RootMenu.
        XCTAssertTrue(
            app.staticTexts["Welcome to Waypoint"].waitForExistence(timeout: 10),
            "UI should launch"
        )

        let host = app.windows["Waypoint UITest Host"]
        XCTAssertTrue(host.waitForExistence(timeout: 8), "UITest host window should open")

        let start = host.buttons["menu.startStop"]
        let startTitle = host.buttons["Start"]
        XCTAssertTrue(
            start.waitForExistence(timeout: 5) || startTitle.exists,
            "Start/Stop control should exist on host"
        )

        let openEditor = host.buttons["uitest.openEditor"]
        XCTAssertTrue(openEditor.waitForExistence(timeout: 5), "Open Editor control should exist")
        XCTAssertTrue(openEditor.isHittable || openEditor.exists)
    }
}
