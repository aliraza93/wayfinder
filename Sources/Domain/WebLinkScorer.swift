import Foundation

/// Scores discovered web nav elements for read-only crawl priority.
public enum WebLinkScorer: Sendable {
    public static func score(
        element: WebNavElement,
        snapshot: WebPageSnapshot,
        settings: ChromeNavigationSettings,
        visited: Set<String>,
        depth: Int
    ) -> WebNavCandidate {
        let href = element.href ?? element.identity
        let normalized = URLNormalizer.normalize(href)
        let domain = URLNormalizer.host(of: normalized.isEmpty ? snapshot.url : normalized)
        let safeName = WebLinkSafetyFilter.isSafe(name: element.name, href: href)
        let safeDomain = WebLinkSafetyFilter.isAllowedDomain(
            href: href,
            currentURL: snapshot.url,
            settings: settings
        )
        let pathAllowed = !settings.excludedPathPrefixes.contains { prefix in
            normalized.lowercased().contains(prefix.lowercased())
        }
        let safe = safeName && safeDomain && pathAllowed && depth <= settings.maxDepth
        let alreadyVisited = visited.contains(normalized) || visited.contains(element.identity)

        var priority = 0
        if safe { priority += 10 }
        if !alreadyVisited { priority += 8 }
        if safeDomain { priority += 6 }

        let name = element.name.lowercased()
        let path = normalized.lowercased()

        switch settings.profile {
        case .documentation:
            priority += docsBoost(name: name, role: element.role, path: path)
        case .githubRepository:
            priority += githubBoost(
                name: name,
                path: path,
                kind: snapshot.kind,
                settings: settings
            )
        case .generalWebsite:
            priority += generalBoost(name: name, role: element.role)
        case .custom:
            priority += generalBoost(name: name, role: element.role)
            for keyword in settings.preferredLinkKeywords where name.contains(keyword) || path.contains(keyword) {
                priority += 12
            }
        }

        for keyword in settings.preferredLinkKeywords where name.contains(keyword) || path.contains(keyword) {
            priority += 5
        }

        if element.role == .pagination {
            priority += settings.profile == .documentation ? 4 : 2
        }

        let typeLabel = typeLabel(for: element, path: path, kind: snapshot.kind)
        return WebNavCandidate(
            element: element,
            domain: domain,
            depth: depth,
            parentURL: URLNormalizer.normalize(snapshot.url),
            priority: priority,
            visited: alreadyVisited,
            safe: safe,
            typeLabel: typeLabel
        )
    }

    public static func rankedCandidates(
        snapshot: WebPageSnapshot,
        settings: ChromeNavigationSettings,
        visited: Set<String>,
        depth: Int
    ) -> [WebNavCandidate] {
        snapshot.allCandidates
            .map {
                score(
                    element: $0,
                    snapshot: snapshot,
                    settings: settings,
                    visited: visited,
                    depth: depth
                )
            }
            .filter(\.safe)
            .filter { !$0.visited }
            .sorted { $0.priority > $1.priority }
    }

    private static func docsBoost(name: String, role: WebNavRole, path: String) -> Int {
        var p = 0
        if role == .navigation { p += 10 }
        if name.contains("next") || name.contains("previous") || name.contains("prev") { p += 14 }
        if name.contains("toc") || name.contains("contents") || name.contains("guide") { p += 8 }
        if path.contains("/docs") || path.contains("/documentation") { p += 8 }
        return p
    }

    private static func githubBoost(
        name: String,
        path: String,
        kind: WebPageKind,
        settings: ChromeNavigationSettings
    ) -> Int {
        var p = 0
        if path.contains("github.com") { p += 4 }
        if path.contains("/blob/") {
            p += settings.crawlSourceFiles ? 12 : -20
        }
        if path.contains("/tree/") {
            p += settings.crawlRepositoryDirectories ? 14 : -20
        }
        if name == "readme" || path.lowercased().contains("readme") {
            p += 16
        }
        if path.contains("/issues") {
            p += settings.crawlIssues ? 6 : -30
        }
        if settings.githubStrategy == .selectedDirectories {
            for dir in settings.selectedDirectories {
                let needle = dir.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if path.contains("/\(needle)/") || path.hasSuffix("/\(needle)") || name.hasPrefix(needle) {
                    p += 18
                }
            }
        }
        if kind == .githubRepoRoot || kind == .githubTree {
            if name.hasSuffix("/") || path.contains("/tree/") { p += 4 }
        }
        return p
    }

    private static func generalBoost(name: String, role: WebNavRole) -> Int {
        var p = 0
        if role == .navigation { p += 6 }
        if role == .link { p += 3 }
        if name.contains("learn") || name.contains("docs") || name.contains("guide") { p += 5 }
        return p
    }

    private static func typeLabel(for element: WebNavElement, path: String, kind: WebPageKind) -> String {
        if path.contains("/blob/") { return "sourceFile" }
        if path.contains("/tree/") { return "directory" }
        if element.role == .pagination { return "pagination" }
        if element.role == .navigation { return "navigation" }
        if kind == .documentation { return "documentation" }
        return element.role.rawValue
    }
}
