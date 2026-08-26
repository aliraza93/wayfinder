import Foundation

/// Hard deny filter for Chrome link / button activation (read-only crawl only).
public enum WebLinkSafetyFilter: Sendable {
    /// Multi-word / phrase denials (substring OK).
    private static let deniedPhrases: [String] = [
        "log out", "logout", "sign out", "signout", "sign in", "log in", "login",
        "buy now", "add to cart", "send message", "send email", "post comment",
        "account settings", "create pull request", "new pull request", "merge pull request",
        "close issue", "delete issue", "new issue",
        "commit changes", "create commit",
        "install app", "cancel subscription",
        "close tab", "close window", "new tab", "go back", "go forward",
    ]

    /// Whole-token denials — avoids rejecting `CreateUser.php` / `settings.swift` file names.
    private static let deniedTokens: Set<String> = [
        "delete", "destroy", "purchase", "checkout", "payment", "buy",
        "submit", "publish", "upload", "download", "follow", "like", "invite", "share",
        "billing", "authorize", "unsubscribe", "reload", "refresh",
        "comment", "reply",
    ]

    /// Exact-label denials for short action words that appear in file names as substrings.
    private static let deniedExactLabels: Set<String> = [
        "create", "update", "save", "remove", "commit", "merge", "push", "settings",
    ]

    private static let deniedPathSubstrings: [String] = [
        "/logout", "/signout", "/sign-out",
        "/login", "/signin", "/sign-in", "/session",
        "/checkout", "/cart", "/billing", "/payment",
        "/settings", "/account",
        "/pull/new", "/compare", "/actions/new",
        "/issues/new", "/discussions/new",
        "/delete", "/destroy",
    ]

    public static func isSafe(name: String, href: String?) -> Bool {
        if ChromeBrowserUINames.matches(name: name) {
            return false
        }
        let lowerName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for phrase in deniedPhrases where lowerName.contains(phrase) {
            return false
        }
        if deniedExactLabels.contains(lowerName) {
            return false
        }
        let tokens = Set(
            lowerName
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { !$0.isEmpty }
        )
        if !tokens.isDisjoint(with: deniedTokens) {
            // Allow source-looking names: token present but name looks like a file.
            if !looksLikeSourceOrDirectoryName(lowerName) {
                return false
            }
        }
        // Exact action labels that are also tokens (Create button vs CreateUser.php).
        if tokens.count == 1, let only = tokens.first, deniedExactLabels.contains(only) {
            return false
        }
        if let href {
            let path = href.lowercased()
            for needle in deniedPathSubstrings {
                if path.contains(needle) { return false }
            }
        }
        return true
    }

    private static func looksLikeSourceOrDirectoryName(_ name: String) -> Bool {
        if name.contains(".") { return true }
        if name.hasSuffix("/") { return true }
        if name.contains("/") { return true }
        return false
    }

    /// Whether the element may be clicked for navigation (surface + classification + domain).
    public static func isActivatable(
        element: WebNavElement,
        currentURL: String,
        policy: DomainPolicy
    ) -> Bool {
        guard element.surface == .pageContent else { return false }
        guard element.classification != .browserUI else { return false }
        guard element.classification != .dangerousAction else { return false }
        guard element.classification != .form else { return false }
        guard element.classification != .actionButton else { return false }
        guard element.classification != .unknown else { return false }
        guard element.classification != .externalLink else {
            return policy.allowExternalLinks && !policy.currentDomainOnly
                && policy.allows(href: element.href ?? element.identity, currentURL: currentURL)
        }
        guard WebElementClassifier.isActivatable(element.classification) else { return false }
        guard isSafe(name: element.name, href: element.href) else { return false }
        return policy.allows(href: element.href ?? element.identity, currentURL: currentURL)
    }

    public static func isAllowedDomain(
        href: String,
        currentURL: String,
        settings: ChromeNavigationSettings
    ) -> Bool {
        settings.domainPolicy.allows(href: href, currentURL: currentURL)
    }
}
