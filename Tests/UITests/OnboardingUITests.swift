import XCTest

/// XCUITest: permission onboarding window happy path.
final class OnboardingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnboardingWindowExposesRequestAndStatus() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitesting"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Welcome to Tiktik Ghora"].waitForExistence(timeout: 10),
            "Onboarding should show welcome copy"
        )

        let request = app.buttons["Request Accessibility…"]
        XCTAssertTrue(request.waitForExistence(timeout: 5), "Request button should exist")

        let host = app.windows["Tiktik Ghora UITest Host"]
        if host.waitForExistence(timeout: 3) {
            let open = host.buttons["uitest.openOnboarding"]
            if open.exists { open.click() }
        }

        let hasStatus =
            app.staticTexts["Accessibility required"].exists
            || app.staticTexts["Accessibility granted"].exists
            || app.staticTexts["Checking Accessibility…"].exists
            || app.staticTexts.matching(NSPredicate(format: "identifier == %@", "onboarding.status")).firstMatch.exists
        XCTAssertTrue(hasStatus, "Onboarding status should be visible")
    }
}
