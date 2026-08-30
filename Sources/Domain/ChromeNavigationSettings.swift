import Foundation

/// High-level Chrome crawl profile (changes scoring weights, not Cursor behavior).
public enum ChromeNavigationProfile: String, Equatable, Sendable, Codable, CaseIterable {
    case documentation
    case githubRepository
    case generalWebsite
    case custom
}

/// How to treat links outside the current / allowed domains.
public enum ChromeExternalDomainPolicy: String, Equatable, Sendable, Codable, CaseIterable {
    case blocked
    case allowlist
}

/// GitHub repository crawl order.
public enum GitHubCrawlStrategy: String, Equatable, Sendable, Codable, CaseIterable {
    case breadthFirst
    case depthFirst
    case selectedDirectories
}

/// User settings for smart Chrome / browser web navigation.
public struct ChromeNavigationSettings: Equatable, Sendable {
    public var enabled: Bool
    public var profile: ChromeNavigationProfile
    public var allowedDomains: [String]
    /// Explicit denylist — always blocked even if same-site heuristics would allow.
    public var blockedDomains: [String]
    public var externalDomainPolicy: ChromeExternalDomainPolicy
    /// Prefer current host only (default). Mapped into `DomainPolicy.currentDomainOnly`.
    public var currentDomainOnly: Bool
    /// Opt-in external hosts (default false).
    public var allowExternalLinks: Bool
    public var maxDepth: Int
    public var maxPages: Int
    public var maxTimePerPageSeconds: Double
    public var maxScrollsPerPage: Int
    public var crawlDocumentation: Bool
    public var crawlSourceFiles: Bool
    public var crawlRepositoryDirectories: Bool
    public var crawlIssues: Bool
    public var githubStrategy: GitHubCrawlStrategy
    public var selectedDirectories: [String]
    public var preferredLinkKeywords: [String]
    public var excludedPathPrefixes: [String]

    public init(
        enabled: Bool = true,
        profile: ChromeNavigationProfile = .generalWebsite,
        allowedDomains: [String] = [],
        blockedDomains: [String] = [],
        externalDomainPolicy: ChromeExternalDomainPolicy = .blocked,
        currentDomainOnly: Bool = true,
        allowExternalLinks: Bool = false,
        maxDepth: Int = 3,
        maxPages: Int = 20,
        maxTimePerPageSeconds: Double = 180,
        maxScrollsPerPage: Int = 40,
        crawlDocumentation: Bool = true,
        crawlSourceFiles: Bool = true,
        crawlRepositoryDirectories: Bool = true,
        crawlIssues: Bool = false,
        githubStrategy: GitHubCrawlStrategy = .breadthFirst,
        selectedDirectories: [String] = ["app/", "src/", "routes/", "tests/"],
        preferredLinkKeywords: [String] = [],
        excludedPathPrefixes: [String] = []
    ) {
        self.enabled = enabled
        self.profile = profile
        self.allowedDomains = allowedDomains
        self.blockedDomains = blockedDomains
        self.externalDomainPolicy = externalDomainPolicy
        self.currentDomainOnly = currentDomainOnly
        self.allowExternalLinks = allowExternalLinks
        self.maxDepth = maxDepth
        self.maxPages = maxPages
        self.maxTimePerPageSeconds = maxTimePerPageSeconds
        self.maxScrollsPerPage = maxScrollsPerPage
        self.crawlDocumentation = crawlDocumentation
        self.crawlSourceFiles = crawlSourceFiles
        self.crawlRepositoryDirectories = crawlRepositoryDirectories
        self.crawlIssues = crawlIssues
        self.githubStrategy = githubStrategy
        self.selectedDirectories = selectedDirectories
        self.preferredLinkKeywords = preferredLinkKeywords
        self.excludedPathPrefixes = excludedPathPrefixes
    }

    public static let `default` = ChromeNavigationSettings()

    /// Derived domain gate used by the crawl filter.
    public var domainPolicy: DomainPolicy {
        domainPolicy(augmentingForURL: "")
    }

    /// Domain gate with profile-aware allowlist (GitHub profile always includes github.com).
    public func domainPolicy(augmentingForURL url: String) -> DomainPolicy {
        var domains = allowedDomains
        let host = URLNormalizer.host(of: url)
        let onGitHub = host == "github.com" || host.hasSuffix(".github.com")
        if profile == .githubRepository || onGitHub {
            if !domains.contains(where: { DomainPolicy.hostsMatch($0, "github.com") }) {
                domains.append("github.com")
            }
        }
        return DomainPolicy(
            currentDomainOnly: currentDomainOnly,
            allowedDomains: domains,
            blockedDomains: blockedDomains,
            allowExternalLinks: allowExternalLinks || externalDomainPolicy == .allowlist
        )
    }

    public mutating func normalize() {
        maxDepth = min(max(1, maxDepth), 25)
        maxPages = min(max(1, maxPages), 200)
        maxTimePerPageSeconds = min(max(15, maxTimePerPageSeconds), 1_800)
        maxScrollsPerPage = min(max(5, maxScrollsPerPage), 200)
        allowedDomains = Self.normalizeDomains(allowedDomains)
        blockedDomains = Self.normalizeDomains(blockedDomains)
        if allowExternalLinks {
            currentDomainOnly = false
        }
        if externalDomainPolicy == .allowlist, !allowedDomains.isEmpty {
            // Allowlist mode still requires explicit domains; keep currentDomainOnly for same-site.
        }
        preferredLinkKeywords = preferredLinkKeywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        excludedPathPrefixes = excludedPathPrefixes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        selectedDirectories = selectedDirectories
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.hasSuffix("/") ? $0 : $0 + "/" }
    }

    public static func normalizeDomains(_ domains: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in domains {
            let host = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
                .split(separator: "/")
                .first
                .map(String.init) ?? ""
            guard !host.isEmpty, !seen.contains(host) else { continue }
            seen.insert(host)
            result.append(host)
        }
        return result
    }
}
