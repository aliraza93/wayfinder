import XCTest
@testable import Domain

final class ChromeIntelligenceV2Tests: XCTestCase {
    func testGitHubRepoActivatesDirectoryBeforeScroll() {
        var settings = ChromeNavigationSettings(
            enabled: true,
            profile: .generalWebsite,
            maxDepth: 5,
            maxPages: 20,
            maxTimePerPageSeconds: 600,
            maxScrollsPerPage: 40,
            crawlSourceFiles: true,
            crawlRepositoryDirectories: true
        )
        settings.normalize()
        var session = ChromeCrawlSession(settings: settings, now: Date())
        let snap = WebPageSnapshot(
            url: "https://github.com/acme/app",
            title: "acme/app",
            links: [
                WebNavElement(
                    identity: "https://github.com/acme/app/tree/main/app",
                    role: .link,
                    name: "app/",
                    href: "https://github.com/acme/app/tree/main/app",
                    centerX: 40,
                    centerY: 120,
                    surface: .pageContent,
                    classification: .repositoryDirectory
                ),
                WebNavElement(
                    identity: "https://github.com/acme/app/blob/main/README.md",
                    role: .link,
                    name: "README.md",
                    href: "https://github.com/acme/app/blob/main/README.md",
                    centerX: 40,
                    centerY: 160,
                    surface: .pageContent,
                    classification: .sourceCodeFile
                ),
            ],
            kind: .githubRepoRoot
        )
        session.applySnapshot(snap, now: Date())
        XCTAssertEqual(session.settings.profile, .githubRepository)

        let decision = session.nextDecision(now: Date())
        guard case .activate = decision else {
            return XCTFail("expected activate before scroll, got \(decision)")
        }
        XCTAssertTrue(
            session.lastIntent == .openRepositoryDirectory
                || session.lastIntent == .openSourceFile
                || session.lastIntent == .openPage
        )
    }

    func testSourceFileNameWithoutHrefIsClassified() {
        let kind = WebElementClassifier.classify(
            name: "User.php",
            href: nil,
            role: .link,
            surface: .pageContent,
            pageURL: "https://github.com/acme/app/tree/main/app/Models",
            pageKind: .githubTree
        )
        XCTAssertEqual(kind, .sourceCodeFile)
    }

    func testCreateUserPhpIsNotDeniedByCreateSubstring() {
        XCTAssertTrue(WebLinkSafetyFilter.isSafe(name: "CreateUser.php", href: nil))
        XCTAssertFalse(WebLinkSafetyFilter.isSafe(name: "Create", href: nil))
        XCTAssertFalse(WebLinkSafetyFilter.isSafe(name: "Create pull request", href: "/pull/new"))
    }

    func testDocumentationSidebarPreferredOverScroll() {
        var settings = ChromeNavigationSettings(
            profile: .generalWebsite,
            allowedDomains: ["laravel.com"],
            maxScrollsPerPage: 40
        )
        settings.normalize()
        var session = ChromeCrawlSession(settings: settings, now: Date())
        let snap = WebPageSnapshot(
            url: "https://laravel.com/docs",
            title: "Docs",
            navigation: [
                WebNavElement(
                    identity: "https://laravel.com/docs/routing",
                    role: .navigation,
                    name: "Routing",
                    href: "https://laravel.com/docs/routing",
                    centerX: 20,
                    centerY: 200,
                    surface: .pageContent,
                    classification: .documentationLink
                ),
            ],
            kind: .documentation
        )
        session.applySnapshot(snap, now: Date())
        let decision = session.nextDecision(now: Date())
        if case .activate(let id, _, _) = decision {
            XCTAssertTrue(id.contains("routing"))
        } else {
            XCTFail("expected documentation activate, got \(decision)")
        }
        XCTAssertEqual(session.lastIntent, .openDocumentationSection)
    }

    func testBlobPageUsesKeysNotScrollWheel() {
        var settings = ChromeNavigationSettings(
            profile: .githubRepository,
            maxScrollsPerPage: 40,
            crawlSourceFiles: true
        )
        settings.normalize()
        var session = ChromeCrawlSession(settings: settings, now: Date())
        let blob = WebPageSnapshot(
            url: "https://github.com/acme/app/blob/main/User.php",
            title: "User.php",
            kind: .githubBlob
        )
        session.applySnapshot(blob, now: Date())
        XCTAssertTrue(session.readingSource)
        XCTAssertGreaterThan(session.pageReadWeight, 0.7)
        XCTAssertGreaterThan(session.pageKeyBudget, 4)
        // No pending links → key traverse (not scroll-wheel).
        let decision = session.nextDecision(now: Date())
        guard case .keyTraverse = decision else {
            return XCTFail("expected keyTraverse for source review, got \(decision)")
        }
    }

    func testLongerPagesGetHigherReadWeight() {
        let short = WebPageSnapshot(url: "https://example.com", title: "Home", kind: .generic)
        let long = WebPageSnapshot(
            url: "https://github.com/acme/app/blob/main/VeryLong.swift",
            title: "VeryLong.swift",
            headings: (0..<20).map {
                WebNavElement(identity: "h\($0)", role: .heading, name: "H\($0)", centerX: 0, centerY: Double($0))
            },
            links: (0..<40).map {
                WebNavElement(
                    identity: "https://github.com/acme/app/blob/main/f\($0).swift",
                    role: .link,
                    name: "f\($0).swift",
                    href: "https://github.com/acme/app/blob/main/f\($0).swift",
                    centerX: 0,
                    centerY: Double($0),
                    surface: .pageContent,
                    classification: .sourceCodeFile
                )
            },
            scrollContainers: [
                WebNavElement(identity: "s1", role: .scrollContainer, name: "code", centerX: 0, centerY: 0),
                WebNavElement(identity: "s2", role: .scrollContainer, name: "code", centerX: 0, centerY: 1),
            ],
            kind: .githubBlob
        )
        XCTAssertGreaterThan(long.estimatedReadWeight, short.estimatedReadWeight)
    }

    func testBlobPageScrollsOnlyAfterPendingEmpty() {
        var settings = ChromeNavigationSettings(
            profile: .githubRepository,
            maxScrollsPerPage: 40,
            crawlSourceFiles: true
        )
        settings.normalize()
        var session = ChromeCrawlSession(settings: settings, now: Date())
        let blob = WebPageSnapshot(
            url: "https://github.com/acme/app/blob/main/User.php",
            title: "User.php",
            links: [
                WebNavElement(
                    identity: "https://github.com/acme/app/blob/main/Post.php",
                    role: .link,
                    name: "Post.php",
                    href: "https://github.com/acme/app/blob/main/Post.php",
                    centerX: 10,
                    centerY: 10,
                    surface: .pageContent,
                    classification: .sourceCodeFile
                ),
            ],
            kind: .githubBlob
        )
        session.applySnapshot(blob, now: Date())
        XCTAssertTrue(session.readingSource)
        let first = session.nextDecision(now: Date())
        guard case .activate = first else {
            return XCTFail("sibling source file should win over key traverse, got \(first)")
        }
    }

    func testPreviewNavigationListsPendingTargets() {
        var settings = ChromeNavigationSettings(profile: .githubRepository)
        settings.normalize()
        var session = ChromeCrawlSession(settings: settings, now: Date())
        session.applySnapshot(
            WebPageSnapshot(
                url: "https://github.com/acme/app",
                title: "repo",
                links: [
                    WebNavElement(
                        identity: "https://github.com/acme/app/tree/main/app",
                        role: .link,
                        name: "app/",
                        href: "https://github.com/acme/app/tree/main/app",
                        centerX: 1,
                        centerY: 1,
                        surface: .pageContent,
                        classification: .repositoryDirectory
                    ),
                    WebNavElement(
                        identity: "https://github.com/acme/app/blob/main/README.md",
                        role: .link,
                        name: "README.md",
                        href: "https://github.com/acme/app/blob/main/README.md",
                        centerX: 1,
                        centerY: 2,
                        surface: .pageContent,
                        classification: .sourceCodeFile
                    ),
                ],
                kind: .githubRepoRoot
            ),
            now: Date()
        )
        let preview = session.previewNavigation(limit: 10)
        XCTAssertFalse(preview.isEmpty)
        XCTAssertTrue(preview.contains { $0.contains("README") || $0.contains("app") })
    }

    func testBrowserChromeStillBlocked() {
        let blocked = ["Back", "Forward", "Reload", "Close Tab", "New Tab", "Extensions", "Chrome Menu"]
        for name in blocked {
            XCTAssertEqual(
                WebElementClassifier.classify(
                    name: name,
                    href: nil,
                    role: .button,
                    surface: .browserUI,
                    pageURL: "https://github.com/acme/app",
                    pageKind: .githubRepoRoot
                ),
                .browserUI
            )
            XCTAssertFalse(WebLinkSafetyFilter.isSafe(name: name, href: nil), name)
        }
    }

    func testStrategySelectorAdaptsProfile() {
        XCTAssertEqual(
            WebPageStrategySelector.adaptedProfile(for: .githubTree, current: .generalWebsite),
            .githubRepository
        )
        XCTAssertEqual(
            WebPageStrategySelector.adaptedProfile(for: .documentation, current: .generalWebsite),
            .documentation
        )
        XCTAssertEqual(
            WebPageStrategySelector.adaptedProfile(for: .githubBlob, current: .custom),
            .custom
        )
    }

    func testVisitKeyIgnoresCoordinateJitter() {
        let a = WebNavElement(
            identity: "AXLink:User.php:40:120",
            role: .link,
            name: "User.php",
            centerX: 40,
            centerY: 120,
            surface: .pageContent,
            classification: .sourceCodeFile
        )
        let b = WebNavElement(
            identity: "AXLink:User.php:41:118",
            role: .link,
            name: "User.php",
            centerX: 41,
            centerY: 118,
            surface: .pageContent,
            classification: .sourceCodeFile
        )
        XCTAssertEqual(ChromeVisitKey.forElement(a), ChromeVisitKey.forElement(b))
        XCTAssertEqual(ChromeVisitKey.forElement(a), "name:user.php")
    }

    func testDoesNotReactivateSameFileWithJitteredIdentity() {
        var settings = ChromeNavigationSettings(profile: .githubRepository, maxPages: 20)
        settings.normalize()
        var session = ChromeCrawlSession(settings: settings, now: Date())
        let first = WebPageSnapshot(
            url: "https://github.com/acme/app/tree/main/app",
            title: "app",
            links: [
                WebNavElement(
                    identity: "AXLink:User.php:10:10",
                    role: .link,
                    name: "User.php",
                    centerX: 10,
                    centerY: 10,
                    surface: .pageContent,
                    classification: .sourceCodeFile
                ),
                WebNavElement(
                    identity: "AXLink:Post.php:10:40",
                    role: .link,
                    name: "Post.php",
                    centerX: 10,
                    centerY: 40,
                    surface: .pageContent,
                    classification: .sourceCodeFile
                ),
            ],
            kind: .githubTree
        )
        session.applySnapshot(first, now: Date())
        let d1 = session.nextDecision(now: Date())
        guard case .activate(let id1, _, _) = d1 else {
            return XCTFail("expected first activate, got \(d1)")
        }
        session.noteActivationCompleted()
        // Simulate successful navigation into the chosen file, then return to the directory.
        let opened = id1.contains("User.php")
            ? "https://github.com/acme/app/blob/main/app/User.php"
            : "https://github.com/acme/app/blob/main/app/Post.php"
        session.applySnapshot(
            WebPageSnapshot(url: opened, title: "file", kind: .githubBlob),
            now: Date()
        )
        // Return to directory; User.php identity jittered — must open the other file.
        let second = WebPageSnapshot(
            url: "https://github.com/acme/app/tree/main/app",
            title: "app",
            links: [
                WebNavElement(
                    identity: "AXLink:User.php:12:11",
                    role: .link,
                    name: "User.php",
                    centerX: 12,
                    centerY: 11,
                    surface: .pageContent,
                    classification: .sourceCodeFile
                ),
                WebNavElement(
                    identity: "AXLink:Post.php:10:40",
                    role: .link,
                    name: "Post.php",
                    centerX: 10,
                    centerY: 40,
                    surface: .pageContent,
                    classification: .sourceCodeFile
                ),
            ],
            kind: .githubTree
        )
        session.applySnapshot(second, now: Date())
        let d2 = session.nextDecision(now: Date())
        guard case .activate(let id2, _, _) = d2 else {
            return XCTFail("expected second activate, got \(d2)")
        }
        XCTAssertNotEqual(id1, id2)
        XCTAssertTrue(
            (id1.contains("User.php") && id2.contains("Post.php"))
                || (id1.contains("Post.php") && id2.contains("User.php"))
        )
    }

    func testSwitchesTabsMultipleTimesInsteadOfOneShot() {
        var settings = ChromeNavigationSettings(maxPages: 20, maxScrollsPerPage: 5)
        settings.normalize()
        var session = ChromeCrawlSession(settings: settings, now: Date())
        session.maxTabSwitches = 4
        session.applySnapshot(
            WebPageSnapshot(url: "https://example.com/a", title: "A"),
            now: Date()
        )
        session.scrollsOnPage = 40
        var switches = 0
        for _ in 0..<6 {
            let decision = session.nextDecision(now: Date())
            if case .switchTab = decision {
                switches += 1
                session.noteActivationCompleted()
                session.applySnapshot(
                    WebPageSnapshot(url: "https://example.com/a", title: "A"),
                    now: Date()
                )
                session.scrollsOnPage = 40
            } else if case .yieldToUniversal = decision {
                break
            } else if case .inspect = decision {
                session.applySnapshot(
                    WebPageSnapshot(url: "https://example.com/a", title: "A"),
                    now: Date()
                )
                session.scrollsOnPage = 40
            }
        }
        XCTAssertGreaterThanOrEqual(switches, 2)
    }

    func testPrepareForNewBrowserDwellKeepsVisitedMemory() {
        var settings = ChromeNavigationSettings()
        settings.normalize()
        var session = ChromeCrawlSession(settings: settings, now: Date())
        session.visitedURLs.insert("https://github.com/acme/app/blob/main/User.php")
        session.visitedTargetKeys.insert("name:user.php")
        session.visitedTabKeys.insert("https://github.com/acme/app")
        session.pending = []
        session.prepareForNewBrowserDwell(now: Date())
        XCTAssertTrue(session.needsInspect)
        XCTAssertTrue(session.visitedURLs.contains("https://github.com/acme/app/blob/main/User.php"))
        XCTAssertTrue(session.visitedTargetKeys.contains("name:user.php"))
        XCTAssertEqual(session.tabSwitchesAttempted, 0)
    }
}
