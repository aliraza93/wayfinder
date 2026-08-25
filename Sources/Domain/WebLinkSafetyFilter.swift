import Foundation

/// Hard deny filter for Chrome link / button activation (read-only crawl only).
public enum WebLinkSafetyFilter: Sendable {
    private static let deniedNameSubstrings: [String] = [
        "log out", "logout", "sign out", "signout",
        "delete", "remove", "destroy",
        "purchase", "buy now", "checkout", "add to cart", "payment",
        "submit", "send message", "send email", "post comment",
        "account settings", "settings", "billing",
        "create pull request", "new pull request", "merge pull request",
        "close issue", "delete issue", "new issue",
        "commit changes", "create commit", "push",
        "upload", "install app", "authorize",
        "unsubscribe", "cancel subscription",
    ]

    private static let deniedPathSubstrings: [String] = [
        "/logout", "/signout", "/sign-out",
        "/login", "/signin", "/sign-in", "/session",
        "/checkout", "/cart", "/billing", "/payment",
        "/settings", "/account", "/billing",
        "/pull/new", "/compare", "/actions/new",
        "/issues/new", "/discussions/new",
        "/delete", "/destroy",
    ]

    public static func isSafe(name: String, href: String?) -> Bool {
        let lowerName = name.lowercased()
        for needle in deniedNameSubstrings {
            if lowerName.contains(needle) { return false }
        }
        if let href {
            let path = href.lowercased()
            for needle in deniedPathSubstrings {
                if path.contains(needle) { return false }
            }
        }
        return true
    }

    public static func isAllowedDomain(
        href: String,
        currentURL: String,
        settings: ChromeNavigationSettings
    ) -> Bool {
        let targetHost = URLNormalizer.host(of: href)
        guard !targetHost.isEmpty else {
            // Relative / unknown — treat as same-page safe if name is safe.
            return true
        }
        let currentHost = URLNormalizer.host(of: currentURL)
        if !currentHost.isEmpty, hostsMatch(targetHost, currentHost) {
            return true
        }
        let allowed = settings.allowedDomains
        if allowed.contains(where: { hostsMatch(targetHost, $0) }) {
            return true
        }
        switch settings.externalDomainPolicy {
        case .blocked:
            return false
        case .allowlist:
            return allowed.contains(where: { hostsMatch(targetHost, $0) })
        }
    }

    private static func hostsMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        if a.hasSuffix("." + b) || b.hasSuffix("." + a) { return true }
        let ra = URLNormalizer.registrableDomain(of: "https://\(a)")
        let rb = URLNormalizer.registrableDomain(of: "https://\(b)")
        return !ra.isEmpty && ra == rb
    }
}
