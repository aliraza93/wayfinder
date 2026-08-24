import XCTest
@testable import Domain

final class ReviewWorkspaceTests: XCTestCase {
    func testDwellNormalizeEnsuresMinLessThanMax() {
        var settings = ReviewWorkspaceSettings(dwellMinSeconds: 100, dwellMaxSeconds: 50)
        settings.normalize()
        XCTAssertLessThan(settings.dwellMinSeconds, settings.dwellMaxSeconds)
    }

    func testSequentialQueueFilesThenTabs() {
        var settings = ReviewWorkspaceSettings(
            workspacePath: "/tmp/proj",
            filePaths: ["a.swift", "b.swift"],
            chromeTabLabels: ["Docs", "GitHub"],
            targetOrder: .sequential
        )
        settings.normalize()
        let selector = ReviewTargetSelector(
            settings: settings,
            editorBundleID: "editor",
            browserBundleID: "com.google.Chrome"
        )
        let queue = selector.makeQueue()
        XCTAssertEqual(queue.count, 4)
        XCTAssertEqual(queue[0].identity, "a.swift")
        XCTAssertEqual(queue[2].identity, "Docs")
    }

    func testControllerOpensFileThenCrawls() {
        var settings = ReviewWorkspaceSettings(
            filePaths: ["/tmp/a.swift"],
            chromeTabLabels: [],
            dwellMinSeconds: 30,
            dwellMaxSeconds: 40,
            speed: .fast
        )
        settings.normalize()
        var controller = ReviewSessionController(
            settings: settings,
            queue: [
                .editorFile(path: "/tmp/a.swift", displayName: "a.swift"),
            ],
            editorBundleID: "com.todesktop.x",
            browserBundleID: nil
        )
        let now = Date()
        let focus = controller.nextPick(now: now)
        XCTAssertEqual(focus?.metaKind, "applicationFocused")
        if case .activateApp(let id) = focus?.action {
            XCTAssertEqual(id, "com.todesktop.x")
        } else {
            XCTFail("expected activateApp")
        }
        let open = controller.nextPick(now: now)
        XCTAssertEqual(open?.metaKind, "fileOpened")
        if case .openExistingFile(let path) = open?.action {
            XCTAssertEqual(path, "/tmp/a.swift")
        } else {
            XCTFail("expected openExistingFile")
        }
        let crawl = controller.nextPick(now: now)
        XCTAssertEqual(crawl?.metaKind, "navigationExecuted")
    }

    func testSpeedPresetsAreFixedIntervals() {
        XCTAssertEqual(NavigationSpeedPreset.slow.defaultIntervalSeconds, 0.85)
        XCTAssertEqual(NavigationSpeedPreset.normal.defaultIntervalSeconds, 0.35)
        XCTAssertEqual(NavigationSpeedPreset.fast.defaultIntervalSeconds, 0.12)
        var settings = ReviewWorkspaceSettings(speed: .custom, customIntervalSeconds: 0.5)
        settings.normalize()
        XCTAssertEqual(settings.actionIntervalSeconds, 0.5)
    }

    func testReadAndReviewDefaultName() {
        XCTAssertEqual(ReadAndReviewWorkspace.workflowName, "Read & Review Workspace")
    }
}
