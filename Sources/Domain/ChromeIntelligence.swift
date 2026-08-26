import Foundation

/// High-level Chrome explorer intent (planner vocabulary — not browser chrome actions).
public enum ChromeNavigationIntent: String, Equatable, Sendable {
    case openPage
    case openInternalLink
    case openRepositoryDirectory
    case openSourceFile
    case openDocumentationSection
    case openPagination
    case scroll
    case returnToParent
    case switchExistingTab
    case skip
    case inspect
}

/// Explicit Chrome explorer state for debugging / UI.
public enum ChromeExplorerState: String, Equatable, Sendable {
    case idle
    case discoveringWorkspace
    case discoveringTabs
    case inspectingPage
    case buildingNavigationTargets
    case selectingTarget
    case navigating
    case reviewingContent
    case scrollingContent
    case discoveringMore
    case completed
    case blocked
    case error
}

/// Read-only Chrome tab group descriptor (never mutate groups).
public struct ChromeTabGroup: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var color: String
    public var collapsed: Bool
    public var tabIdentities: [String]

    public init(
        id: String,
        title: String,
        color: String = "",
        collapsed: Bool = false,
        tabIdentities: [String] = []
    ) {
        self.id = id
        self.title = title
        self.color = color
        self.collapsed = collapsed
        self.tabIdentities = tabIdentities
    }
}

/// Debug snapshot for Chrome Intelligence (identity only — never body text).
public struct ChromeExplorerDebugSnapshot: Equatable, Sendable {
    public var state: ChromeExplorerState
    public var currentURL: String
    public var pageType: WebPageKind
    public var intent: ChromeNavigationIntent
    public var discoveredCount: Int
    public var safeCount: Int
    public var blockedCount: Int
    public var nextTarget: String
    public var lastRejection: String
    public var tabGroupCount: Int

    public init(
        state: ChromeExplorerState = .idle,
        currentURL: String = "",
        pageType: WebPageKind = .generic,
        intent: ChromeNavigationIntent = .inspect,
        discoveredCount: Int = 0,
        safeCount: Int = 0,
        blockedCount: Int = 0,
        nextTarget: String = "",
        lastRejection: String = "",
        tabGroupCount: Int = 0
    ) {
        self.state = state
        self.currentURL = currentURL
        self.pageType = pageType
        self.intent = intent
        self.discoveredCount = discoveredCount
        self.safeCount = safeCount
        self.blockedCount = blockedCount
        self.nextTarget = nextTarget
        self.lastRejection = lastRejection
        self.tabGroupCount = tabGroupCount
    }

    public static let empty = ChromeExplorerDebugSnapshot()
}

/// Stable keys so the same file/tab is not revisited when AX identities jitter.
public enum ChromeVisitKey: Sendable {
    public static func forElement(_ element: WebNavElement) -> String {
        if let href = element.href {
            let normalized = URLNormalizer.normalize(href)
            if !normalized.isEmpty { return normalized }
        }
        let normalizedIdentity = URLNormalizer.normalize(element.identity)
        if !normalizedIdentity.isEmpty,
           normalizedIdentity.contains("://") || normalizedIdentity.hasPrefix("/")
        {
            return normalizedIdentity
        }
        let name = element.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !name.isEmpty {
            if GitHubURLParser.isSourceFilePath(name)
                || name.hasSuffix("/")
                || element.classification == .sourceCodeFile
                || element.classification == .repositoryDirectory
                || element.classification == .documentationLink
            {
                return "name:\(name)"
            }
        }
        if let stripped = stripCoordinateSuffix(element.identity), !stripped.isEmpty {
            return stripped.lowercased()
        }
        return element.identity.lowercased()
    }

    public static func forPage(url: String, title: String) -> String {
        let normalized = URLNormalizer.normalize(url)
        if !normalized.isEmpty { return normalized }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? "" : "tab:\(trimmed)"
    }

    private static func stripCoordinateSuffix(_ identity: String) -> String? {
        let parts = identity.split(separator: ":")
        guard parts.count >= 3,
              Int(parts[parts.count - 1]) != nil,
              Int(parts[parts.count - 2]) != nil
        else {
            return nil
        }
        return parts.dropLast(2).joined(separator: ":")
    }
}

/// Maps page kind → preferred profile and scoring strategy.
public enum WebPageStrategySelector: Sendable {
    public static func adaptedProfile(
        for kind: WebPageKind,
        current: ChromeNavigationProfile
    ) -> ChromeNavigationProfile {
        if current == .custom { return .custom }
        switch kind {
        case .githubRepoRoot, .githubTree, .githubBlob, .githubOther, .githubIssues:
            return .githubRepository
        case .documentation:
            return .documentation
        case .generic:
            return current == .githubRepository || current == .documentation
                ? current
                : .generalWebsite
        }
    }

    public static func intent(
        for candidate: WebNavCandidate,
        pageKind: WebPageKind
    ) -> ChromeNavigationIntent {
        switch candidate.classificationKind {
        case .sourceCodeFile:
            return .openSourceFile
        case .repositoryDirectory:
            return .openRepositoryDirectory
        case .documentationLink, .tableOfContents:
            return .openDocumentationSection
        case .pagination:
            return .openPagination
        case .internalNavigation, .articleLink:
            return pageKind == .documentation ? .openDocumentationSection : .openInternalLink
        default:
            return .openPage
        }
    }
}

extension WebNavCandidate {
    public var classificationKind: WebElementKind {
        element.classification
    }

    public var visitKey: String {
        ChromeVisitKey.forElement(element)
    }
}
