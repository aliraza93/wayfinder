import XCTest
@testable import Domain

final class TimedReviewNavigationTests: XCTestCase {
    func testMakeControllerBuildsFromSettings() {
        var settings = ReviewWorkspaceSettings(
            filePaths: ["One.swift"],
            chromeTabLabels: ["Tab"],
            targetOrder: .sequential
        )
        settings.normalize()
        let controller = TimedReviewNavigation.makeController(
            settings: settings,
            targets: [
                TargetApp(bundleID: "editor", classification: .editor),
                TargetApp(bundleID: "com.google.Chrome", classification: .browser),
            ]
        )
        XCTAssertEqual(controller.queue.count, 2)
    }
}
