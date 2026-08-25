import XCTest
@testable import Domain

final class ChromeNavigationTests: XCTestCase {
    func testURLNormalizerStripsFragmentAndTracking() {
        let raw = "https://github.com/org/repo/blob/main/App.swift?utm_source=x#L10"
        let normalized = URLNormalizer.normalize(raw)
        XCTAssertFalse(normalized.contains("utm_source"))
        XCTAssertFalse(normalized.contains("#"))
        XCTAssertTrue(normalized.contains("github.com/org/repo/blob/main/App.swift"))
    }

    func testSafetyFilterDeniesLogoutAndCheckout() {
        XCTAssertFalse(WebLinkSafetyFilter.isSafe(name: "Log out", href: "/logout"))
        XCTAssertFalse(WebLinkSafetyFilter.isSafe(name: "Checkout", href: "/cart"))
        XCTAssertTrue(WebLinkSafetyFilter.isSafe(name: "Routing", href: "/docs/routing"))
    }

    func testDomainPolicyBlocksExternalByDefault() {
        var settings = ChromeNavigationSettings(
            allowedDomains: ["laravel.com"],
            externalDomainPolicy: .blocked
        )
        settings.normalize()
        XCTAssertTrue(
            WebLinkSafetyFilter.isAllowedDomain(
                href: "https://laravel.com/docs",
                currentURL: "https://laravel.com/docs/installation",
                settings: settings
            )
        )
        XCTAssertFalse(
            WebLinkSafetyFilter.isAllowedDomain(
                href: "https://evil.example/ads",
                currentURL: "https://laravel.com/docs",
                settings: settings
            )
        )
    }

    func testGitHubParserDetectsBlobAndTree() {
        XCTAssertEqual(
            GitHubURLParser.pageKind(for: "https://github.com/acme/app"),
            .githubRepoRoot
        )
        XCTAssertEqual(
            GitHubURLParser.pageKind(for: "https://github.com/acme/app/tree/main/app"),
            .githubTree
        )
        XCTAssertEqual(
            GitHubURLParser.pageKind(for: "https://github.com/acme/app/blob/main/app/User.php"),
            .githubBlob
        )
    }

    func testScorerPrefersDocsNextLink() {
        let snapshot = WebPageSnapshot(
            url: "https://laravel.com/docs/routing",
            title: "Routing",
            links: [
                WebNavElement(
                    identity: "https://evil.example/x",
                    role: .link,
                    name: "Ads",
                    href: "https://evil.example/x",
                    centerX: 10,
                    centerY: 10
                ),
                WebNavElement(
                    identity: "https://laravel.com/docs/middleware",
                    role: .link,
                    name: "Next",
                    href: "https://laravel.com/docs/middleware",
                    centerX: 20,
                    centerY: 20
                ),
            ],
            kind: .documentation
        )
        var settings = ChromeNavigationSettings(
            profile: .documentation,
            allowedDomains: ["laravel.com"],
            externalDomainPolicy: .blocked
        )
        settings.normalize()
        let ranked = WebLinkScorer.rankedCandidates(
            snapshot: snapshot,
            settings: settings,
            visited: [],
            depth: 1
        )
        XCTAssertEqual(ranked.first?.element.name, "Next")
        XCTAssertFalse(ranked.contains { $0.element.name == "Ads" })
    }

    func testCrawlSessionActivatesSafeLinkThenAvoidsRevisit() {
        var settings = ChromeNavigationSettings(
            enabled: true,
            profile: .documentation,
            allowedDomains: ["docs.example"],
            maxDepth: 5,
            maxPages: 10,
            maxTimePerPageSeconds: 120,
            maxScrollsPerPage: 40
        )
        settings.normalize()
        var session = ChromeCrawlSession(settings: settings, now: Date())
        let snap = WebPageSnapshot(
            url: "https://docs.example/a",
            title: "A",
            links: [
                WebNavElement(
                    identity: "https://docs.example/b",
                    role: .link,
                    name: "Section B",
                    href: "https://docs.example/b",
                    centerX: 100,
                    centerY: 200
                ),
            ],
            kind: .documentation
        )
        session.applySnapshot(snap, now: Date())
        let first = session.nextDecision(now: Date())
        if case .activate(let id, _, _) = first {
            XCTAssertTrue(id.contains("docs.example/b"))
        } else {
            XCTFail("expected activate, got \(first)")
        }
        session.noteActivationCompleted()
        session.applySnapshot(
            WebPageSnapshot(url: "https://docs.example/b", title: "B", kind: .documentation),
            now: Date()
        )
        // Same link should not be pending again as unvisited.
        XCTAssertTrue(session.visitedURLs.contains(URLNormalizer.normalize("https://docs.example/b")))
    }

    func testNewWebActionsAreNonMutating() {
        let actions: [ActionKind] = [
            .inspectWebPage,
            .activateWebNavTarget(identity: "https://example.com", x: 1, y: 2),
            .browserBack,
        ]
        for action in actions {
            XCTAssertFalse(action.capabilityTags.mutatesText)
        }
        XCTAssertEqual(ActionKind.inspectWebPage.capabilityTags.primitive, .none)
        XCTAssertEqual(
            ActionKind.activateWebNavTarget(identity: "x", x: 0, y: 0).capabilityTags.primitive,
            .targetedClick
        )
        XCTAssertEqual(ActionKind.browserBack.capabilityTags.primitive, .navigationChord)
    }
}
