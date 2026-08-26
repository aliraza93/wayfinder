import Foundation

/// Domain allow / block policy for web navigation (same-site by default).
public struct DomainPolicy: Equatable, Sendable {
    /// When true, only the current page’s host (and registrable domain siblings) are allowed
    /// unless listed in `allowedDomains`.
    public var currentDomainOnly: Bool
    public var allowedDomains: [String]
    public var blockedDomains: [String]
    /// When false (default), external hosts are rejected unless allowlisted.
    public var allowExternalLinks: Bool

    public init(
        currentDomainOnly: Bool = true,
        allowedDomains: [String] = [],
        blockedDomains: [String] = [],
        allowExternalLinks: Bool = false
    ) {
        self.currentDomainOnly = currentDomainOnly
        self.allowedDomains = allowedDomains
        self.blockedDomains = blockedDomains
        self.allowExternalLinks = allowExternalLinks
    }

    public static let `default` = DomainPolicy()

    public func allows(href: String, currentURL: String) -> Bool {
        let targetHost = URLNormalizer.host(of: href)
        // Relative / fragment / in-page targets: allowed only when caller already
        // established page-content surface (empty host is not "external").
        if targetHost.isEmpty {
            return true
        }
        if blockedDomains.contains(where: { Self.hostsMatch(targetHost, $0) }) {
            return false
        }
        let currentHost = URLNormalizer.host(of: currentURL)
        if !currentHost.isEmpty, Self.hostsMatch(targetHost, currentHost) {
            return true
        }
        if allowedDomains.contains(where: { Self.hostsMatch(targetHost, $0) }) {
            return true
        }
        if allowExternalLinks, !currentDomainOnly {
            return true
        }
        return false
    }

    public static func hostsMatch(_ a: String, _ b: String) -> Bool {
        let left = a.lowercased()
        let right = b.lowercased()
        if left == right { return true }
        if left.hasSuffix("." + right) || right.hasSuffix("." + left) { return true }
        let ra = URLNormalizer.registrableDomain(of: "https://\(left)")
        let rb = URLNormalizer.registrableDomain(of: "https://\(right)")
        return !ra.isEmpty && ra == rb
    }
}
