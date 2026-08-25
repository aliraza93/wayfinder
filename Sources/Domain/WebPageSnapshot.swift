import Foundation

/// Role of an accessible navigation element (best-effort AX mapping).
public enum WebNavRole: String, Equatable, Sendable, Codable {
    case link
    case button
    case heading
    case navigation
    case pagination
    case expandable
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

    public init(
        identity: String,
        role: WebNavRole,
        name: String,
        href: String? = nil,
        centerX: Double,
        centerY: Double
    ) {
        self.identity = identity
        self.role = role
        self.name = name
        self.href = href
        self.centerX = centerX
        self.centerY = centerY
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
        self.kind = kind
        self.inspectedAt = inspectedAt
    }

    public static let empty = WebPageSnapshot()

    public var isEmpty: Bool {
        url.isEmpty && links.isEmpty && navigation.isEmpty && pagination.isEmpty && buttons.isEmpty
    }

    public var allCandidates: [WebNavElement] {
        navigation + links + buttons + pagination + sections
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
