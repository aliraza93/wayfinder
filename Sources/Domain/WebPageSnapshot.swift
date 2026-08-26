import Foundation

/// Role of an accessible navigation element (best-effort AX mapping).
public enum WebNavRole: String, Equatable, Sendable, Codable {
    case link
    case button
    case heading
    case navigation
    case pagination
    case expandable
    case tab
    case scrollContainer
    case unknown
}

/// Coarse page kind inferred from URL / structure (never from body text).
public enum WebPageKind: String, Equatable, Sendable, Codable {
    case generic
    case documentation
    case githubRepoRoot
    case githubTree
    case githubBlob
    case githubIssues
    case githubOther
}

/// One discoverable control on the page (identity + geometry for a targeted click).
public struct WebNavElement: Equatable, Sendable {
    /// Stable identity for visited tracking / logging (normalized URL or synthetic key).
    public var identity: String
    public var role: WebNavRole
    /// Accessible name used only for scoring / safety — never logged as document body.
    public var name: String
    public var href: String?
    public var centerX: Double
    public var centerY: Double
    /// Browser chrome vs page content — browser UI must never be activated.
    public var surface: WebNavSurface
    public var classification: WebElementKind

    public init(
        identity: String,
        role: WebNavRole,
        name: String,
        href: String? = nil,
        centerX: Double,
        centerY: Double,
        surface: WebNavSurface = .unknown,
        classification: WebElementKind = .unknown
    ) {
        self.identity = identity
        self.role = role
        self.name = name
        self.href = href
        self.centerX = centerX
        self.centerY = centerY
        self.surface = surface
        self.classification = classification
    }
}

/// Best-effort accessible snapshot of the frontmost browser page.
public struct WebPageSnapshot: Equatable, Sendable {
    public var url: String
    public var title: String
    public var headings: [WebNavElement]
    public var navigation: [WebNavElement]
    public var links: [WebNavElement]
    public var buttons: [WebNavElement]
    public var pagination: [WebNavElement]
    public var sections: [WebNavElement]
    public var tabs: [WebNavElement]
    public var scrollContainers: [WebNavElement]
    public var kind: WebPageKind
    public var inspectedAt: Date

    public init(
        url: String = "",
        title: String = "",
        headings: [WebNavElement] = [],
        navigation: [WebNavElement] = [],
        links: [WebNavElement] = [],
        buttons: [WebNavElement] = [],
        pagination: [WebNavElement] = [],
        sections: [WebNavElement] = [],
        tabs: [WebNavElement] = [],
        scrollContainers: [WebNavElement] = [],
        kind: WebPageKind = .generic,
        inspectedAt: Date = Date()
    ) {
        self.url = url
        self.title = title
        self.headings = headings
        self.navigation = navigation
        self.links = links
        self.buttons = buttons
        self.pagination = pagination
        self.sections = sections
        self.tabs = tabs
        self.scrollContainers = scrollContainers
        self.kind = kind
        self.inspectedAt = inspectedAt
    }

    public static let empty = WebPageSnapshot()

    public var isEmpty: Bool {
        url.isEmpty
            && links.isEmpty
            && navigation.isEmpty
            && pagination.isEmpty
            && buttons.isEmpty
            && headings.isEmpty
            && tabs.isEmpty
    }

    /// Elements eligible for scored activation — page content only, never browser UI.
    public var allCandidates: [WebNavElement] {
        (navigation + links + pagination + sections)
            .filter { $0.surface != .browserUI }
            .filter { $0.classification != .browserUI }
            .filter { WebElementClassifier.isActivatable($0.classification) || $0.classification == .unknown }
    }

    /// Stable fingerprint for infinite-scroll “did content change?” checks (no body text).
    public var contentFingerprint: String {
        let linkPart = links.prefix(48).map(\.identity).joined(separator: "\u{1f}")
        let headingPart = headings.prefix(16).map(\.name).joined(separator: "\u{1f}")
        return [
            URLNormalizer.normalize(url),
            title,
            "\(links.count)",
            "\(headings.count)",
            "\(pagination.count)",
            linkPart,
            headingPart,
        ].joined(separator: "\u{1e}")
    }

    public var looksLikeDocumentation: Bool {
        if kind == .documentation { return true }
        if navigation.contains(where: {
            let n = $0.name.lowercased()
            return n.contains("contents") || n.contains("sidebar") || n.contains("toc")
        }) {
            return true
        }
        if pagination.contains(where: {
            let n = $0.name.lowercased()
            return n.contains("next") || n.contains("prev")
        }) {
            return true
        }
        return false
    }

    /// Heuristic read length (0.2…1.4) from structure only — never document body.
    /// Longer pages/files get higher weight so the workflow stays longer.
    public var estimatedReadWeight: Double {
        var weight = 0.35
        switch kind {
        case .githubBlob:
            weight += 0.55
        case .documentation:
            weight += 0.35
        case .githubTree, .githubRepoRoot:
            weight += 0.15
        case .githubIssues, .githubOther:
            weight += 0.2
        case .generic:
            break
        }
        if looksLikeDocumentation { weight += 0.15 }
        weight += min(0.35, Double(links.count) / 70.0)
        weight += min(0.2, Double(headings.count) / 35.0)
        weight += min(0.2, Double(scrollContainers.count) * 0.08)
        weight += min(0.15, Double(sections.count) / 40.0)
        return min(1.4, max(0.2, weight))
    }
}

/// Planner-facing candidate with priority / safety flags.
public struct WebNavCandidate: Equatable, Sendable {
    public var element: WebNavElement
    public var domain: String
    public var depth: Int
    public var parentURL: String
    public var priority: Int
    public var visited: Bool
    public var safe: Bool
    public var typeLabel: String

    public init(
        element: WebNavElement,
        domain: String,
        depth: Int,
        parentURL: String,
        priority: Int,
        visited: Bool,
        safe: Bool,
        typeLabel: String
    ) {
        self.element = element
        self.domain = domain
        self.depth = depth
        self.parentURL = parentURL
        self.priority = priority
        self.visited = visited
        self.safe = safe
        self.typeLabel = typeLabel
    }
}

/// Normalize URLs for visited-set comparison (strip fragment, default ports, trailing slash).
public enum URLNormalizer: Sendable {
    public static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard var components = URLComponents(string: trimmed) else {
            return trimmed.lowercased()
        }
        components.fragment = nil
        if let query = components.queryItems, !query.isEmpty {
            // Drop common tracking / session params; keep path identity.
            let drop: Set<String> = [
                "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
                "fbclid", "gclid", "session", "token", "access_token",
            ]
            components.queryItems = query.filter { !drop.contains($0.name.lowercased()) }
            if components.queryItems?.isEmpty == true {
                components.queryItems = nil
            }
        }
        if components.scheme == nil, trimmed.contains(".") {
            components.scheme = "https"
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.port == 80 || components.port == 443 {
            components.port = nil
        }
        var path = components.path
        if path.count > 1, path.hasSuffix("/") {
            path.removeLast()
            components.path = path
        }
        return components.string ?? trimmed.lowercased()
    }

    public static func host(of raw: String) -> String {
        let normalized = normalize(raw)
        guard let host = URLComponents(string: normalized)?.host else {
            return ""
        }
        return host.lowercased()
    }

    public static func registrableDomain(of raw: String) -> String {
        let host = host(of: raw)
        let parts = host.split(separator: ".")
        guard parts.count >= 2 else { return host }
        return parts.suffix(2).joined(separator: ".")
    }
}
