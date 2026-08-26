import Domain
import XCTest

final class WorkspaceDiscoveryTests: XCTestCase {
    func testPriorityOrdersCursorChromeFinderPreviewSafari() {
        XCTAssertEqual(
            WorkspaceDiscoveryPlanner.priority(
                bundleID: "com.todesktop.230313mzl4w4u92",
                classification: .editor
            ),
            0
        )
        XCTAssertEqual(
            WorkspaceDiscoveryPlanner.priority(
                bundleID: "com.google.Chrome",
                classification: .browser
            ),
            1
        )
        XCTAssertEqual(
            WorkspaceDiscoveryPlanner.priority(
                bundleID: "com.apple.finder",
                classification: .finder
            ),
            2
        )
        XCTAssertEqual(
            WorkspaceDiscoveryPlanner.priority(
                bundleID: "com.apple.Preview",
                classification: .generic
            ),
            3
        )
        XCTAssertEqual(
            WorkspaceDiscoveryPlanner.priority(
                bundleID: "com.apple.Safari",
                classification: .browser
            ),
            4
        )
    }

    func testDiscoverTargetsEditorExtractsFiles() {
        let windows = [
            DiscoveredWindowInfo(title: "User.php — MyApplication", index: 0),
            DiscoveredWindowInfo(title: "Controller.php — MyApplication", index: 1),
        ]
        let targets = WorkspaceDiscoveryPlanner.discoverTargets(
            displayName: "Cursor",
            bundleID: "com.todesktop.230313mzl4w4u92",
            processID: 42,
            classification: .editor,
            accessibilityStatus: .readable,
            windows: windows
        )

        XCTAssertTrue(targets.contains { $0.kind == .application && $0.displayName == "Cursor" })
        XCTAssertTrue(targets.contains { $0.kind == .file && $0.displayName == "User.php" })
        XCTAssertTrue(targets.contains { $0.kind == .file && $0.displayName == "Controller.php" })
        XCTAssertTrue(targets.allSatisfy { !$0.approved })
    }

    func testDiscoverTargetsBrowserProducesTabs() {
        let windows = [DiscoveredWindowInfo(title: "Laravel Docs", index: 0)]
        let targets = WorkspaceDiscoveryPlanner.discoverTargets(
            displayName: "Chrome",
            bundleID: "com.google.Chrome",
            processID: 7,
            classification: .browser,
            accessibilityStatus: .readable,
            windows: windows
        )

        XCTAssertTrue(targets.contains { $0.kind == .tab && $0.displayName == "Laravel Docs" })
        XCTAssertTrue(targets.contains { $0.kind == .navigation && $0.displayName == "Laravel Docs" })
    }

    func testApprovalMutations() {
        var snapshot = WorkspaceDiscoverySnapshot(
            apps: [
                DiscoveredAppDetail(
                    displayName: "Chrome",
                    bundleID: "com.google.Chrome",
                    processID: 1,
                    classification: .browser,
                    isActive: true,
                    accessibilityStatus: .readable,
                    windows: [],
                    targets: [
                        NavigationTarget(
                            id: "a1",
                            kind: .application,
                            displayName: "Chrome",
                            bundleID: "com.google.Chrome",
                            classification: .browser,
                            approved: false
                        ),
                        NavigationTarget(
                            id: "t1",
                            kind: .tab,
                            displayName: "GitHub",
                            bundleID: "com.google.Chrome",
                            classification: .browser,
                            approved: false
                        ),
                    ]
                ),
            ]
        )

        snapshot.setApproved("t1", approved: true)
        XCTAssertEqual(snapshot.approvedTargets.map(\.id), ["t1"])

        snapshot.setAllApproved(true)
        XCTAssertEqual(snapshot.approvedTargets.count, 2)
    }

    func testSortAppsPrioritizesPreferredBundleIDs() {
        let apps = [
            DiscoveredAppDetail(
                displayName: "Notes",
                bundleID: "com.apple.Notes",
                processID: 3,
                classification: .generic,
                isActive: false,
                accessibilityStatus: .limited,
                windows: [],
                targets: []
            ),
            DiscoveredAppDetail(
                displayName: "Chrome",
                bundleID: "com.google.Chrome",
                processID: 2,
                classification: .browser,
                isActive: true,
                accessibilityStatus: .readable,
                windows: [],
                targets: []
            ),
            DiscoveredAppDetail(
                displayName: "Cursor",
                bundleID: "com.todesktop.230313mzl4w4u92",
                processID: 1,
                classification: .editor,
                isActive: false,
                accessibilityStatus: .readable,
                windows: [],
                targets: []
            ),
        ]
        let sorted = WorkspaceDiscoveryPlanner.sortApps(apps)
        XCTAssertEqual(sorted.map(\.displayName), ["Cursor", "Chrome", "Notes"])
    }
}
