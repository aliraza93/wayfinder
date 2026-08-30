import Foundation

/// Where an AX / nav element lives relative to Chrome.
public enum WebNavSurface: String, Equatable, Sendable, Codable {
    /// Inside the web page content (AXWebArea / document).
    case pageContent
    /// Chrome-owned UI: tabs, toolbar, omnibox, window controls, etc.
    case browserUI
    case unknown
}

/// Semantic classification of a discoverable web element.
public enum WebElementKind: String, Equatable, Sendable, Codable {
    case internalNavigation
    case documentationLink
    case repositoryDirectory
    case sourceCodeFile
    case articleLink
    case pagination
    case tableOfContents
    case externalLink
    case form
    case actionButton
    case dangerousAction
    case browserUI
    case unknown
}

/// Pure-logic classifier — decides whether an element may be activated for read-only crawl.
public enum WebElementClassifier: Sendable {
    /// Kinds allowed for automatic activation by default.
    public static let defaultAllowed: Set<WebElementKind> = [
        .internalNavigation,
        .documentationLink,
        .repositoryDirectory,
        .sourceCodeFile,
        .articleLink,
        .pagination,
        .tableOfContents,
    ]

    public static func isActivatable(_ kind: WebElementKind) -> Bool {
        defaultAllowed.contains(kind)
    }

    public static func classify(
        name: String,
        href: String?,
        role: WebNavRole,
        surface: WebNavSurface,
        pageURL: String,
        pageKind: WebPageKind
    ) -> WebElementKind {
        if surface == .browserUI {
            return .browserUI
        }
        if ChromeBrowserUINames.matches(name: name, role: role) {
            return .browserUI
        }
        if !WebLinkSafetyFilter.isSafe(name: name, href: href) {
            return .dangerousAction
        }

        let lowerName = name.lowercased()
        let path = (href ?? "").lowercased()
        let currentHost = URLNormalizer.host(of: pageURL)
        let targetHost = URLNormalizer.host(of: href ?? "")

        if role == .pagination || Self.isPaginationName(lowerName) {
            return .pagination
        }

        if Self.isTableOfContents(name: lowerName) {
            return .tableOfContents
        }

        // GitHub file rows often expose the filename without AXURL — classify by name too.
        if path.contains("/blob/")
            || GitHubURLParser.isSourceFilePath(href ?? path)
            || GitHubURLParser.isSourceFilePath(name)
        {
            return .sourceCodeFile
        }
        let onGitHubTree = pageKind == .githubTree || pageKind == .githubRepoRoot || pageKind == .githubOther
        if path.contains("/tree/")
            || (onGitHubTree && (lowerName.hasSuffix("/") || looksLikeDirectoryName(lowerName)
                || (!lowerName.contains(".") && !lowerName.isEmpty && lowerName.count <= 48
                    && !lowerName.contains(" "))))
        {
            return .repositoryDirectory
        }

        if !targetHost.isEmpty, !currentHost.isEmpty,
           !DomainPolicy.hostsMatch(targetHost, currentHost),
           !Self.isSameRegistrableDomain(targetHost, currentHost)
        {
            return .externalLink
        }

        if pageKind == .documentation
            || path.contains("/docs")
            || path.contains("/documentation")
            || lowerName.contains("docs")
            || lowerName.contains("guide")
            || lowerName.contains("reference")
        {
            return .documentationLink
        }

        if role == .navigation || role == .link {
            if pageKind == .generic || pageKind == .documentation {
                return lowerName.isEmpty ? .unknown : .articleLink
            }
            return .internalNavigation
        }

        if role == .button {
            // Nav-like page buttons (docs sidebar, menus) — not submit/actions.
            if Self.isNavLikeButton(name: lowerName) {
                if pageKind == .documentation || lowerName.contains("doc") || lowerName.contains("guide") {
                    return .documentationLink
                }
                return .internalNavigation
            }
            return .actionButton
        }

        if role == .heading {
            // Headings are structural — not click targets unless they wrap a safe link (handled as link).
            return .unknown
        }

        if role == .expandable {
            return .unknown
        }

        return .unknown
    }

    private static func isPaginationName(_ lower: String) -> Bool {
        lower == "next" || lower == "previous" || lower == "prev"
            || lower.contains("next page") || lower.contains("previous page")
            || lower.contains("load more") || lower.contains("show more")
    }

    private static func isTableOfContents(name: String) -> Bool {
        name.contains("table of contents") || name == "toc" || name.contains("contents")
            || name.contains("sidebar") && name.contains("nav")
    }

    private static func looksLikeDirectoryName(_ lower: String) -> Bool {
        if lower.hasSuffix("/") { return true }
        // Common top-level repo folders without trailing slash in AX names.
        let known = [
            "app", "src", "lib", "libs", "tests", "test", "routes", "config",
            "database", "resources", "public", "docs", "documentation",
            "packages", "components", "models", "controllers", "middleware",
            "views", "scripts", "bin", "cmd", "pkg", "internal",
            "http", "services", "utils", "helpers", "types", "hooks",
            "store", "stores", "api", "core", "shared", "common",
        ]
        return known.contains(lower)
    }

    /// In-page nav affordances that are not submit/purchase/auth actions.
    private static func isNavLikeButton(name: String) -> Bool {
        if name.isEmpty { return false }
        if name.contains("submit") || name.contains("sign") || name.contains("log in")
            || name.contains("buy") || name.contains("checkout") || name.contains("delete")
            || name.contains("save") || name.contains("send") || name.contains("post ")
        {
            return false
        }
        return name.contains("nav") || name.contains("menu") || name.contains("sidebar")
            || name.contains("docs") || name.contains("guide") || name.contains("reference")
            || name.contains("getting started") || name.contains("api")
            || name.contains("next") || name.contains("previous") || name.contains("prev")
            || name.contains("contents") || name.contains("section")
            || name.contains("chapter") || name.contains("learn")
    }

    private static func isSameRegistrableDomain(_ a: String, _ b: String) -> Bool {
        DomainPolicy.hostsMatch(a, b)
    }
}

/// Name / role denylist for Chrome-owned controls (Domain-pure; no coordinates).
public enum ChromeBrowserUINames: Sendable {
    private static let exact: Set<String> = [
        "back", "forward", "reload", "refresh", "stop", "home",
        "new tab", "close", "close tab", "close window",
        "minimize", "maximize", "zoom",
        "chrome", "google chrome",
        "extensions", "bookmarks", "bookmark this tab",
        "downloads", "history", "settings", "customize and control google chrome",
        "main menu", "chrome menu", "app menu",
        "profile", "accounts", "people",
        "address", "omnibox", "search or type a url", "search google or type a url",
    ]

    private static let substrings: [String] = [
        "close tab", "close window", "close other", "close all",
        "new tab", "new window", "new incognito",
        "reload this", "refresh this",
        "go back", "go forward",
        "bookmark", "bookmarks bar",
        "extension", "extensions",
        "download", "downloads",
        "chrome settings", "browser settings",
        "manage profiles", "switch person",
        "omnibox", "address bar",
        "tab strip", "window control",
    ]

    public static func matches(name: String, role: WebNavRole = .unknown) -> Bool {
        let lower = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.isEmpty {
            // Nameless buttons near chrome are unsafe to activate.
            if role == .button || role == .tab { return true }
            return false
        }
        if exact.contains(lower) { return true }
        for needle in substrings where lower.contains(needle) {
            return true
        }
        // Single-character close affordances.
        if lower == "×" || lower == "x" || lower == "✕" { return true }
        if role == .tab { return true }
        return false
    }
}
