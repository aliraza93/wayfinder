import Domain
import XCTest

final class DiscoveryNavigationPlanTests: XCTestCase {
    func testFoundCountsAndPreviewPlan() {
        let snapshot = WorkspaceDiscoverySnapshot(
            apps: [
                DiscoveredAppDetail(
                    displayName: "Cursor",
                    bundleID: "com.todesktop.230313mzl4w4u92",
                    processID: 1,
                    classification: .editor,
                    isActive: true,
                    accessibilityStatus: .readable,
                    windows: [],
                    targets: [
                        NavigationTarget(
                            kind: .application,
                            displayName: "Cursor",
                            bundleID: "com.todesktop.230313mzl4w4u92",
                            classification: .editor,
                            approved: true
                        ),
                        NavigationTarget(
                            kind: .file,
                            displayName: "User.php",
                            bundleID: "com.todesktop.230313mzl4w4u92",
                            classification: .editor,
                            approved: true
                        ),
                        NavigationTarget(
                            kind: .file,
                            displayName: "Controller.php",
                            bundleID: "com.todesktop.230313mzl4w4u92",
                            classification: .editor,
                            approved: false
                        ),
                    ]
                ),
                DiscoveredAppDetail(
                    displayName: "Chrome",
                    bundleID: "com.google.Chrome",
                    processID: 2,
                    classification: .browser,
                    isActive: false,
                    accessibilityStatus: .readable,
                    windows: [],
                    targets: [
                        NavigationTarget(
                            kind: .tab,
                            displayName: "Laravel Docs",
                            bundleID: "com.google.Chrome",
                            classification: .browser,
                            approved: true
                        ),
                    ]
                ),
            ]
        )

        let plan = DiscoveryNavigationPlan.buildPlan(from: snapshot)
        XCTAssertEqual(plan.map(\.displayLine), [
            "Cursor → User.php",
            "Chrome → Laravel Docs",
        ])

        let counts = DiscoveryNavigationPlan.appTargetCounts(from: snapshot)
        XCTAssertEqual(counts.map(\.name), ["Cursor", "Chrome"])
        XCTAssertEqual(counts.map(\.count), [2, 1])
    }

    func testEstimateCapsAtDuration() {
        let estimate = DiscoveryNavigationPlan.estimate(
            approvedCount: 37,
            dwellMinSeconds: 30,
            dwellMaxSeconds: 180,
            maxDurationSeconds: 600,
            untilStopped: false
        )
        XCTAssertEqual(estimate.approvedCount, 37)
        XCTAssertEqual(estimate.estimatedSeconds, 600)
        XCTAssertTrue(estimate.formattedDuration.contains("minute"))
    }

    func testEstimateUntilStoppedShowsReadingHint() {
        let estimate = DiscoveryNavigationPlan.estimate(
            approvedCount: 10,
            dwellMinSeconds: 30,
            dwellMaxSeconds: 30,
            maxDurationSeconds: nil,
            untilStopped: true
        )
        XCTAssertTrue(estimate.formattedDuration.contains("until stopped"))
    }
}
