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
            targetOrder: .sequential,
            discoverRunningApps: false
        )
        settings.normalize()
        let selector = ReviewTargetSelector(
            settings: settings,
            editorBundleID: "editor",
            browserBundleID: "com.google.Chrome"
        )
        let queue = selector.makeQueue()
        XCTAssertEqual(queue.count, 4)
        // Interleaved: editor file, browser tab, editor file, browser tab
        XCTAssertEqual(queue[0].identity, "a.swift")
        XCTAssertEqual(queue[1].identity, "Docs")
        XCTAssertEqual(queue[2].identity, "b.swift")
        XCTAssertEqual(queue[3].identity, "GitHub")
    }

    func testPlannerMergesDiscoveredApps() {
        var settings = ReviewWorkspaceSettings(
            filePaths: [],
            chromeTabLabels: [],
            discoverRunningApps: true,
            discovery: DiscoveryScope(includeFinder: true, includePreview: true, includeOther: false)
        )
        settings.normalize()
        let queue = NavigationPlanner.buildQueue(
            settings: settings,
            discovered: [
                DiscoveredApplication(
                    bundleID: "com.apple.finder",
                    displayName: "Finder",
                    classification: .finder,
                    isActive: false
                ),
                DiscoveredApplication(
                    bundleID: "com.apple.Preview",
                    displayName: "Preview",
                    classification: .generic,
                    isActive: false
                ),
                DiscoveredApplication(
                    bundleID: "com.apple.dt.Xcode",
                    displayName: "Xcode",
                    classification: .editor,
                    isActive: false
                ),
                DiscoveredApplication(
                    bundleID: "com.apple.systempreferences",
                    displayName: "Settings",
                    classification: .generic,
                    isActive: false
                ),
                DiscoveredApplication(
                    bundleID: "com.apple.TextEdit",
                    displayName: "TextEdit",
                    classification: .generic,
                    isActive: false
                ),
            ],
            workflowTargets: [
                TargetApp(bundleID: "com.todesktop.x", classification: .editor),
            ]
        )
        XCTAssertTrue(queue.contains { $0.identity == "Finder" })
        XCTAssertTrue(queue.contains { $0.identity == "Preview" })
        XCTAssertFalse(queue.contains { $0.identity == "Xcode" })
        XCTAssertFalse(queue.contains { $0.identity == "Settings" })
        XCTAssertFalse(queue.contains { $0.identity == "TextEdit" })
        XCTAssertTrue(queue.contains {
            if case .discoveredApp(let id, _, _) = $0 { return id == "com.todesktop.x" }
            return false
        })
    }

    func testAllowlistOnlyWhenDiscoveryOff() {
        var settings = ReviewWorkspaceSettings(discoverRunningApps: false)
        settings.normalize()
        let queue = NavigationPlanner.buildQueue(
            settings: settings,
            discovered: [
                DiscoveredApplication(
                    bundleID: "com.apple.finder",
                    displayName: "Finder",
                    classification: .finder,
                    isActive: true
                ),
                DiscoveredApplication(
                    bundleID: "com.apple.dt.Xcode",
                    displayName: "Xcode",
                    classification: .editor,
                    isActive: true
                ),
            ],
            workflowTargets: [
                TargetApp(bundleID: "com.todesktop.x", classification: .editor),
                TargetApp(bundleID: "com.google.Chrome", classification: .browser),
            ]
        )
        XCTAssertEqual(queue.count, 2)
        XCTAssertFalse(queue.contains { $0.identity == "Finder" })
        XCTAssertFalse(queue.contains { $0.identity == "Xcode" })
    }

    func testSettingsNeverAllowed() {
        XCTAssertTrue(NavigationAppPolicy.isForbidden("com.apple.systempreferences"))
        XCTAssertTrue(NavigationAppPolicy.isForbidden("com.apple.Preferences"))
        let app = DiscoveredApplication(
            bundleID: "com.apple.systempreferences",
            displayName: "Settings",
            classification: .generic,
            isActive: true
        )
        var settings = ReviewWorkspaceSettings(
            discoverRunningApps: true,
            discovery: DiscoveryScope(includeOther: true)
        )
        settings.normalize()
        XCTAssertFalse(
            NavigationAppPolicy.allowsDiscovered(
                app,
                settings: settings,
                workflowTargets: []
            )
        )
    }

    func testControllerOpensFileThenCrawls() {
        var settings = ReviewWorkspaceSettings(
            filePaths: ["/tmp/a.swift"],
            chromeTabLabels: [],
            dwellMinSeconds: 30,
            dwellMaxSeconds: 40,
            speed: .fast,
            discoverRunningApps: false,
            refreshTargetsBetweenDwells: false
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

    func testDiscoveredAppFocusesBundle() {
        var settings = ReviewWorkspaceSettings(
            dwellMinSeconds: 30,
            dwellMaxSeconds: 40,
            discoverRunningApps: false,
            refreshTargetsBetweenDwells: false
        )
        settings.normalize()
        var controller = ReviewSessionController(
            settings: settings,
            queue: [
                .discoveredApp(
                    bundleID: "com.apple.finder",
                    displayName: "Finder",
                    classification: .finder
                ),
            ]
        )
        let focus = controller.nextPick(now: Date())
        XCTAssertEqual(focus?.metaKind, "applicationFocused")
        if case .activateApp(let id) = focus?.action {
            XCTAssertEqual(id, "com.apple.finder")
        } else {
            XCTFail("expected activateApp for discovered app")
        }
    }

    func testSpeedPresetsAreFixedIntervals() {
        XCTAssertEqual(NavigationSpeedPreset.slow.defaultIntervalSeconds, 0.85)
        XCTAssertEqual(NavigationSpeedPreset.normal.defaultIntervalSeconds, 0.35)
        XCTAssertEqual(NavigationSpeedPreset.fast.defaultIntervalSeconds, 0.12)
        var settings = ReviewWorkspaceSettings(speed: .custom, customIntervalSeconds: 0.5)
        settings.normalize()
        XCTAssertEqual(settings.actionIntervalSeconds, 0.5)
    }

    func testUniversalWorkspaceDefaultName() {
        XCTAssertEqual(
            UniversalWorkspaceNavigation.workflowName,
            "Universal Workspace Navigation"
        )
        XCTAssertEqual(
            ReadAndReviewWorkspace.workflowName,
            UniversalWorkspaceNavigation.workflowName
        )
    }

    func testClassifierRecognizesCommonApps() {
        XCTAssertEqual(ApplicationClassifier.classify(bundleID: "com.google.Chrome"), .browser)
        XCTAssertEqual(ApplicationClassifier.classify(bundleID: "com.apple.Safari"), .browser)
        XCTAssertEqual(ApplicationClassifier.classify(bundleID: "com.apple.finder"), .finder)
        XCTAssertEqual(ApplicationClassifier.classify(bundleID: "com.apple.Preview"), .generic)
        XCTAssertTrue(ApplicationClassifier.isPreview(bundleID: "com.apple.Preview"))
    }

    func testConservativeCrawlSkipsContentClick() {
        let action = NavigationPlanner.progressiveCrawlAction(step: 11, classification: .finder)
        if case .contentClick = action {
            XCTFail("finder crawl must not content-click")
        }
    }

    func testBoundaryRecoveryDoesNotSpamEnd() {
        let tick = NavigationPlanner.progressiveCrawlTick(
            step: 20,
            classification: .editor,
            atBoundary: true,
            consecutiveDown: 20,
            pace: .shortContent
        )
        if case .pageNavigate(.end) = tick.action {
            XCTFail("after End, must not press End again")
        }
        if case .explorerFileSwitch = tick.action {
            // preferred path
        } else {
            XCTAssertTrue(tick.resetsDownStreak || tick.endDwellEarly)
        }
    }

    func testCrawlPrefersTopMidNotEnd() {
        var sawEnd = false
        var sawHomeOrHighlightOrClick = false
        for step in 1...5 {
            let tick = NavigationPlanner.progressiveCrawlTick(
                step: step,
                classification: .editor,
                atBoundary: false,
                consecutiveDown: 0,
                pace: .reading
            )
            if case .pageNavigate(.end) = tick.action { sawEnd = true }
            switch tick.action {
            case .pageNavigate(.home), .highlightNavigate, .contentClick:
                sawHomeOrHighlightOrClick = true
            default:
                break
            }
        }
        XCTAssertFalse(sawEnd, "early crawl must not jump to End")
        XCTAssertTrue(sawHomeOrHighlightOrClick)
    }

    func testInterleaveAlternatesEditorAndBrowser() {
        let interleaved = NavigationPlanner.interleaveByAppClass([
            .discoveredApp(bundleID: "e1", displayName: "E1", classification: .editor),
            .discoveredApp(bundleID: "e2", displayName: "E2", classification: .editor),
            .discoveredApp(bundleID: "b1", displayName: "B1", classification: .browser),
        ])
        XCTAssertEqual(interleaved[0].identity, "E1")
        XCTAssertEqual(interleaved[1].identity, "B1")
        XCTAssertEqual(interleaved[2].identity, "E2")
    }

    func testEditorSurfaceSwitchUsesExplorerOnly() {
        let tick = NavigationPlanner.progressiveCrawlTick(
            step: 20,
            classification: .editor,
            atBoundary: true,
            consecutiveDown: 20,
            pace: .shortContent
        )
        if case .explorerFileSwitch = tick.action {
            // ok
        } else {
            XCTFail("expected explorerFileSwitch for short editor content, got \(tick.action)")
        }
    }

    func testAdaptiveShortContentCutsDwell() {
        var session = AdaptiveSurfaceSession(now: Date(), durationSeconds: 60)
        let settings = ReviewWorkspaceSettings(dwellMinSeconds: 10, dwellMaxSeconds: 40)
        let now = Date()
        session.observe(
            action: .pageNavigate(.end),
            markedBoundary: true,
            settings: settings,
            now: now
        )
        // Simulate little scrolling then boundary.
        session.downwardCount = 3
        session.boundaryCount = 1
        session.observe(
            action: .pageNavigate(.end),
            markedBoundary: true,
            settings: settings,
            now: now
        )
        XCTAssertLessThan(session.endsAt.timeIntervalSince(now), 5)
    }

    func testAdaptiveLongContentExtendsDwell() {
        var session = AdaptiveSurfaceSession(now: Date(), durationSeconds: 10)
        let settings = ReviewWorkspaceSettings(dwellMinSeconds: 20, dwellMaxSeconds: 60)
        let now = Date()
        let before = session.endsAt
        for _ in 0..<12 {
            session.observe(
                action: .scroll(direction: .down, amount: 4),
                markedBoundary: false,
                settings: settings,
                now: now
            )
        }
        XCTAssertGreaterThan(session.endsAt, before)
        XCTAssertEqual(ContentPaceHint.from(session: session, atBoundary: false), .longContent)
    }

    func testFileDwellHelpersProduceRanges() {
        var settings = ReviewWorkspaceSettings(dwellMinSeconds: 20, dwellMaxSeconds: 80)
        settings.normalize()
        let file = settings.randomFileDwellSeconds()
        XCTAssertGreaterThanOrEqual(file, 4)
        XCTAssertLessThanOrEqual(file, 80)
        let pause = settings.randomInterFilePauseSeconds()
        XCTAssertGreaterThanOrEqual(pause, 0.4)
        XCTAssertLessThanOrEqual(pause, 2.2)
    }
}
