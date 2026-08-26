import Domain
import XCTest

final class UniversalNavigationTests: XCTestCase {
    func testApplicationPriorityOrdersCursorBeforeChrome() {
        let queue: [ReviewTarget] = [
            .discoveredApp(
                bundleID: "com.google.Chrome",
                displayName: "Chrome",
                classification: .browser
            ),
            .discoveredApp(
                bundleID: "com.todesktop.230313mzl4w4u92",
                displayName: "Cursor",
                classification: .editor
            ),
            .discoveredApp(
                bundleID: "com.apple.finder",
                displayName: "Finder",
                classification: .finder
            ),
        ]
        let ordered = NavigationPlanner.orderByApplicationPriority(queue)
        XCTAssertEqual(ordered.map(\.identity), ["Cursor", "Chrome", "Finder"])
    }

    func testTargetRotationPrefersLeastVisited() {
        var visited = VisitedTargetTracker()
        visited.markCompleted("app:com.google.Chrome")
        visited.markCompleted("app:com.google.Chrome")
        let queue: [ReviewTarget] = [
            .discoveredApp(
                bundleID: "com.google.Chrome",
                displayName: "Chrome",
                classification: .browser
            ),
            .discoveredApp(
                bundleID: "com.todesktop.230313mzl4w4u92",
                displayName: "Cursor",
                classification: .editor
            ),
        ]
        let ordered = NavigationPlanner.orderForRotation(queue, visited: visited)
        XCTAssertEqual(ordered.first?.identity, "Cursor")
    }

    func testConfiguredPriorityKeepsInputOrder() {
        var settings = ReviewWorkspaceSettings(targetOrder: .configuredPriority)
        settings.normalize()
        let queue: [ReviewTarget] = [
            .discoveredApp(bundleID: "b", displayName: "B", classification: .browser),
            .discoveredApp(bundleID: "a", displayName: "A", classification: .editor),
        ]
        let ordered = NavigationPlanner.orderQueue(queue, settings: settings)
        XCTAssertEqual(ordered.map(\.identity), ["B", "A"])
    }

    func testLifecycleTransitionsOnController() {
        var settings = UniversalWorkflowBridge.defaultSettings
        settings.dwellMinSeconds = 5
        settings.dwellMaxSeconds = 6
        settings.refreshTargetsBetweenDwells = false
        settings.normalize()

        let queue: [ReviewTarget] = [
            .discoveredApp(
                bundleID: "com.todesktop.230313mzl4w4u92",
                displayName: "Cursor",
                classification: .editor
            ),
            .discoveredApp(
                bundleID: "com.google.Chrome",
                displayName: "Chrome",
                classification: .browser
            ),
        ]
        var controller = ReviewSessionController(settings: settings, queue: queue)
        XCTAssertEqual(
            controller.visited.lifecycle(for: "app:com.todesktop.230313mzl4w4u92"),
            .pending
        )

        let now = Date()
        _ = controller.nextPick(now: now) // focus app → active
        XCTAssertEqual(
            controller.visited.lifecycle(for: "app:com.todesktop.230313mzl4w4u92"),
            .active
        )
        _ = controller.nextPick(now: now) // select surface → crawl
        _ = controller.nextPick(now: now.addingTimeInterval(10)) // dwell expired → next
        XCTAssertEqual(controller.targetsCompleted, 1)
        XCTAssertTrue(controller.visited.hasVisited("app:com.todesktop.230313mzl4w4u92"))
        XCTAssertEqual(
            controller.visited.lifecycle(for: "app:com.google.Chrome"),
            .active
        )
    }

    func testRefreshDropsUnavailableDiscoveryExtras() {
        var settings = UniversalWorkflowBridge.defaultSettings
        settings.normalize()
        let previous: [ReviewTarget] = [
            .discoveredApp(
                bundleID: "com.apple.finder",
                displayName: "Finder",
                classification: .finder
            ),
            .discoveredApp(
                bundleID: "com.apple.Preview",
                displayName: "Preview",
                classification: .generic
            ),
        ]
        let refreshed = NavigationPlanner.refreshQueue(
            current: previous[0],
            remainingFromIndex: 0,
            previous: previous,
            settings: settings,
            discovered: [
                DiscoveredApplication(
                    bundleID: "com.apple.finder",
                    displayName: "Finder",
                    classification: .finder,
                    isActive: true
                ),
            ],
            workflowTargets: []
        )
        XCTAssertTrue(refreshed.contains { $0.identity == "Finder" })
        XCTAssertFalse(refreshed.contains { $0.identity == "Preview" })
    }

    func testMergeApprovedSeedsUniversalWorkflow() {
        var workflow = Workflow(
            name: "",
            targets: [],
            steps: [],
            loop: LoopSettings(enabled: true, maxIterations: 1, maxDurationSeconds: 60)
        )
        let approved = [
            NavigationTarget(
                kind: .application,
                displayName: "Chrome",
                bundleID: "com.google.Chrome",
                classification: .browser,
                approved: true
            ),
            NavigationTarget(
                kind: .file,
                displayName: "User.php",
                bundleID: "com.todesktop.x",
                identityPath: "app/User.php",
                classification: .editor,
                approved: true
            ),
            NavigationTarget(
                kind: .tab,
                displayName: "Laravel Docs",
                bundleID: "com.google.Chrome",
                classification: .browser,
                approved: true
            ),
        ]
        UniversalWorkflowBridge.mergeApprovedTargets(into: &workflow, approved: approved)
        XCTAssertEqual(workflow.name, UniversalWorkspaceNavigation.workflowName)
        XCTAssertTrue(workflow.review.discoverRunningApps)
        XCTAssertTrue(workflow.review.refreshTargetsBetweenDwells)
        XCTAssertTrue(workflow.targets.contains { $0.bundleID == "com.google.Chrome" })
        XCTAssertTrue(workflow.review.filePaths.contains("app/User.php"))
        XCTAssertTrue(workflow.review.chromeTabLabels.contains("Laravel Docs"))
    }

    func testTargetSelectorAliasMatchesReviewSelector() {
        let _: TargetSelector.Type = ReviewTargetSelector.self
        XCTAssertEqual(UniversalWorkspaceNavigation.workflowName, "Universal Workspace Navigation")
    }
}
