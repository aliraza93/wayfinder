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
        let classified: WebNavElement = {
            if element.classification != .unknown, element.surface != .unknown {
                return element
            }
            var copy = element
            let surface: WebNavSurface = element.surface == .unknown ? .pageContent : element.surface
            copy.surface = surface
            copy.classification = WebElementClassifier.classify(
                name: element.name,
                href: element.href,
                role: element.role,
                surface: surface,
                pageURL: snapshot.url,
                pageKind: snapshot.kind
            )
            return copy
        }()

        let safe = WebLinkSafetyFilter.isActivatable(
            element: classified,
            currentURL: snapshot.url,
            policy: settings.domainPolicy
        ) && depth <= settings.maxDepth
            && !settings.excludedPathPrefixes.contains { prefix in
                normalized.lowercased().contains(prefix.lowercased())
            }
        let visitKey = ChromeVisitKey.forElement(classified)
        let alreadyVisited = visited.contains(normalized)
            || visited.contains(element.identity)
            || visited.contains(visitKey)
            || (!normalized.isEmpty && visited.contains(normalized))

        var priority = 0
        if safe { priority += 10 }
        if !alreadyVisited { priority += 8 }
        if settings.domainPolicy.allows(href: href, currentURL: snapshot.url) { priority += 6 }

        let name = classified.name.lowercased()
        let path = normalized.lowercased()

        // Score from page kind first so a mis-set profile still navigates GitHub/docs correctly.
        switch snapshot.kind {
        case .githubRepoRoot, .githubTree, .githubBlob, .githubOther, .githubIssues:
            priority += githubBoost(
                name: name,
                path: path.isEmpty ? name : path,
                kind: snapshot.kind,
                settings: settings
            )
        case .documentation:
            priority += docsBoost(name: name, role: classified.role, path: path)
        case .generic:
            break
        }

        switch settings.profile {
        case .documentation:
            if snapshot.kind != .documentation {
                priority += docsBoost(name: name, role: classified.role, path: path)
            }
        case .githubRepository:
            if snapshot.kind == .generic {
                priority += githubBoost(
                    name: name,
                    path: path.isEmpty ? name : path,
                    kind: snapshot.kind,
                    settings: settings
                )
            }
        case .generalWebsite:
            priority += generalBoost(name: name, role: classified.role)
        case .custom:
            priority += generalBoost(name: name, role: classified.role)
            for keyword in settings.preferredLinkKeywords where name.contains(keyword) || path.contains(keyword) {
                priority += 12
            }
        }

        switch classified.classification {
        case .sourceCodeFile: priority += 100
        case .repositoryDirectory: priority += 100
        case .documentationLink, .tableOfContents: priority += 90
        case .internalNavigation: priority += 70
        case .articleLink: priority += 70
        case .pagination: priority += 60
        case .externalLink: priority -= 100
        case .dangerousAction, .form, .actionButton, .browserUI: priority -= 100
        case .unknown: break
        }

        for keyword in settings.preferredLinkKeywords where name.contains(keyword) || path.contains(keyword) {
            priority += 5
        }

        if classified.role == .pagination || classified.classification == .pagination {
            priority += settings.profile == .documentation ? 4 : 2
        }

        let typeLabel = typeLabel(for: classified, path: path, kind: snapshot.kind)
        return WebNavCandidate(
            element: classified,
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
        if role == .heading { p += 7 }
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
        if role == .heading { p += 2 }
        if name.contains("learn") || name.contains("docs") || name.contains("guide") { p += 5 }
        return p
    }

    private static func typeLabel(for element: WebNavElement, path: String, kind: WebPageKind) -> String {
        switch element.classification {
        case .sourceCodeFile: return "sourceFile"
        case .repositoryDirectory: return "directory"
        case .documentationLink, .tableOfContents: return "documentation"
        case .pagination: return "pagination"
        default: break
        }
        if path.contains("/blob/") || GitHubURLParser.isSourceFilePath(path) || GitHubURLParser.isSourceFilePath(element.name) {
            return "sourceFile"
        }
        if path.contains("/tree/") || element.name.hasSuffix("/") { return "directory" }
        if element.role == .pagination { return "pagination" }
        if element.role == .navigation { return "navigation" }
        if element.role == .heading { return "heading" }
        if kind == .documentation { return "documentation" }
        return element.role.rawValue
    }
}
