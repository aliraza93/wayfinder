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
    public var externalDomainPolicy: ChromeExternalDomainPolicy
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
        externalDomainPolicy: ChromeExternalDomainPolicy = .blocked,
        maxDepth: Int = 5,
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
        self.externalDomainPolicy = externalDomainPolicy
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

    public mutating func normalize() {
        maxDepth = min(max(1, maxDepth), 25)
        maxPages = min(max(1, maxPages), 200)
        maxTimePerPageSeconds = min(max(15, maxTimePerPageSeconds), 1_800)
        maxScrollsPerPage = min(max(5, maxScrollsPerPage), 200)
        allowedDomains = Self.normalizeDomains(allowedDomains)
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
        if !crawlIssues {
            crawlIssues = false
        }
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
