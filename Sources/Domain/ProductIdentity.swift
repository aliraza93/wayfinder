import Foundation

/// Display / branding constants. Bundle ID stays `com.twixrsolutions.waypoint` (Accessibility grant).
public enum ProductIdentity: Sendable {
    public static let displayName = "Tiktik Ghora"
    public static let bundleIdentifier = "com.twixrsolutions.waypoint"
    /// Application Support folder (kept for config compatibility until a dedicated migration).
    public static let applicationSupportFolderName = "Waypoint"
    public static let tagline = "Hands-free navigation. Never touches your work."
    public static let dashboardSubtitle = "Smart Workspace Navigation"
    /// Menu bar / sidebar mark — forward gait without a cartoon mascot.
    public static let menuBarSystemImage = "figure.run"
    public static let shortDescription =
        "Native macOS read-only workspace navigation for Cursor, Chrome, and more."
}
