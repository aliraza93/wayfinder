import XCTest
@testable import Domain

/// Architectural safety boundary: Chrome browser UI vs page content.
final class ChromeBrowserUIBoundaryTests: XCTestCase {
    func testBrowserUINamesAreRejected() {
        for name in [
            "Back", "Forward", "Reload", "Close Tab", "Close Window",
            "New Tab", "Profile", "Extensions", "Downloads", "History",
            "Customize and control Google Chrome", "Search Google or type a URL", "×",
        ] {
            XCTAssertTrue(ChromeBrowserUINames.matches(name: name), name)
            XCTAssertFalse(WebLinkSafetyFilter.isSafe(name: name, href: nil), name)
        }
    }

    func testClassifierRejectsBrowserUIAndDangerousActions() {
        XCTAssertEqual(
            WebElementClassifier.classify(
                name: "Back",
                href: nil,
                role: .button,
                surface: .browserUI,
                pageURL: "https://github.com/a/b",
                pageKind: .githubRepoRoot
            ),
            .browserUI
        )
        XCTAssertEqual(
            WebElementClassifier.classify(
                name: "Delete repository",
                href: "/settings",
                role: .button,
                surface: .pageContent,
                pageURL: "https://github.com/a/b",
                pageKind: .githubRepoRoot
            ),
            .dangerousAction
        )
        XCTAssertEqual(
            WebElementClassifier.classify(
                name: "Submit",
                href: "/form",
                role: .button,
                surface: .pageContent,
                pageURL: "https://example.com",
                pageKind: .generic
            ),
            .dangerousAction
        )
    }

    func testClassifierAllowsGitHubSourceAndDocs() {
        XCTAssertEqual(
            WebElementClassifier.classify(
                name: "User.php",
                href: "https://github.com/a/b/blob/main/app/User.php",
                role: .link,
                surface: .pageContent,
                pageURL: "https://github.com/a/b",
                pageKind: .githubRepoRoot
            ),
            .sourceCodeFile
        )
        XCTAssertEqual(
            WebElementClassifier.classify(
                name: "app/",
                href: "https://github.com/a/b/tree/main/app",
                role: .link,
                surface: .pageContent,
                pageURL: "https://github.com/a/b",
                pageKind: .githubRepoRoot
            ),
            .repositoryDirectory
        )
        XCTAssertEqual(
            WebElementClassifier.classify(
                name: "Routing",
                href: "https://laravel.com/docs/routing",
                role: .link,
                surface: .pageContent,
                pageURL: "https://laravel.com/docs",
                pageKind: .documentation
            ),
            .documentationLink
        )
        XCTAssertTrue(WebElementClassifier.isActivatable(.sourceCodeFile))
        XCTAssertTrue(WebElementClassifier.isActivatable(.documentationLink))
        XCTAssertTrue(WebElementClassifier.isActivatable(.repositoryDirectory))
        XCTAssertFalse(WebElementClassifier.isActivatable(.browserUI))
        XCTAssertFalse(WebElementClassifier.isActivatable(.dangerousAction))
        XCTAssertFalse(WebElementClassifier.isActivatable(.externalLink))
        XCTAssertFalse(WebElementClassifier.isActivatable(.unknown))
    }

    func testDomainPolicyDefaultsToCurrentDomainOnly() {
        let policy = DomainPolicy.default
        XCTAssertTrue(policy.currentDomainOnly)
        XCTAssertFalse(policy.allowExternalLinks)
        XCTAssertTrue(
            policy.allows(
                href: "https://github.com/a/b/tree/main/app",
                currentURL: "https://github.com/a/b"
            )
        )
        XCTAssertFalse(
            policy.allows(
                href: "https://youtube.com/watch",
                currentURL: "https://github.com/a/b"
            )
        )
    }

    func testExternalLinkRejectedByDefaultInScorer() {
        let snapshot = WebPageSnapshot(
            url: "https://github.com/a/b",
            title: "Repo",
            links: [
                WebNavElement(
                    identity: "https://youtube.com/x",
                    role: .link,
                    name: "YouTube",
                    href: "https://youtube.com/x",
                    centerX: 10,
                    centerY: 200,
                    surface: .pageContent,
                    classification: .externalLink
                ),
                WebNavElement(
                    identity: "https://github.com/a/b/blob/main/User.php",
                    role: .link,
                    name: "User.php",
                    href: "https://github.com/a/b/blob/main/User.php",
                    centerX: 20,
                    centerY: 220,
                    surface: .pageContent,
                    classification: .sourceCodeFile
                ),
            ],
            kind: .githubRepoRoot
        )
        var settings = ChromeNavigationSettings(profile: .githubRepository)
        settings.normalize()
        let ranked = WebLinkScorer.rankedCandidates(
            snapshot: snapshot,
            settings: settings,
            visited: [],
            depth: 1
        )
        XCTAssertFalse(ranked.contains { $0.element.name == "YouTube" })
        XCTAssertTrue(ranked.contains { $0.element.name == "User.php" })
    }

    func testBrowserUIElementsNeverBecomeCandidates() {
        let snapshot = WebPageSnapshot(
            url: "https://docs.example/a",
            title: "A",
            links: [
                WebNavElement(
                    identity: "close-tab",
                    role: .button,
                    name: "Close Tab",
                    centerX: 900,
                    centerY: 20,
                    surface: .browserUI,
                    classification: .browserUI
                ),
            ],
            buttons: [
                WebNavElement(
                    identity: "back",
                    role: .button,
                    name: "Back",
                    centerX: 40,
                    centerY: 40,
                    surface: .browserUI,
                    classification: .browserUI
                ),
            ],
            tabs: [
                WebNavElement(
                    identity: "tab:Docs",
                    role: .tab,
                    name: "Docs",
                    centerX: 120,
                    centerY: 18,
                    surface: .browserUI,
                    classification: .browserUI
                ),
            ],
            kind: .documentation
        )
        XCTAssertTrue(snapshot.allCandidates.isEmpty)
        var settings = ChromeNavigationSettings()
        settings.normalize()
        let ranked = WebLinkScorer.rankedCandidates(
            snapshot: snapshot,
            settings: settings,
            visited: [],
            depth: 1
        )
        XCTAssertTrue(ranked.isEmpty)
    }

    func testCrawlNeverEmitsBrowserBack() {
        var settings = ChromeNavigationSettings(
            enabled: true,
            profile: .documentation,
            allowedDomains: ["docs.example"],
            maxDepth: 2,
            maxPages: 3,
            maxTimePerPageSeconds: 1,
            maxScrollsPerPage: 1
        )
        settings.normalize()
        var session = ChromeCrawlSession(settings: settings, now: Date())
        session.applySnapshot(
            WebPageSnapshot(url: "https://docs.example/a", title: "A", kind: .documentation),
            now: Date()
        )
        // Exhaust page budget with no pending links.
        session.scrollsOnPage = settings.maxScrollsPerPage
        let decision = session.nextDecision(now: Date().addingTimeInterval(2))
        if case .browserBack = decision {
            XCTFail("browserBack must never be emitted")
        }
        switch decision {
        case .switchTab, .yieldToUniversal, .inspect, .keyTraverse, .wait, .activate:
            break
        case .browserBack:
            XCTFail("browserBack must never be emitted")
        }
    }

    func testDefaultMaxDepthIsThree() {
        XCTAssertEqual(ChromeNavigationSettings.default.maxDepth, 3)
    }
}
