import Foundation

/// Frontmost user-facing app (bundle id + display name).
public struct FrontmostApp: Equatable, Sendable {
    public var bundleID: String
    public var displayName: String

    public init(bundleID: String, displayName: String) {
        self.bundleID = bundleID
        self.displayName = displayName
    }
}

/// Resolves the frontmost app via an injected `RunningAppsProvider`. No activation.
public struct FrontmostAppResolver: Sendable {
    private let provider: any RunningAppsProvider

    public init(provider: any RunningAppsProvider = WorkspaceRunningAppsProvider()) {
        self.provider = provider
    }

    /// Returns the frontmost `.regular` app with a bundle id, if any.
    public func frontmostApp() -> FrontmostApp? {
        Self.resolve(from: provider.runningApps())
    }

    /// Pure mapping — unit-tested with injected lists.
    public static func resolve(from apps: [RunningAppInfo]) -> FrontmostApp? {
        guard let active = apps.first(where: { $0.isActive }),
              active.activationPolicy == .regular,
              let bundleID = active.bundleID,
              !bundleID.isEmpty
        else {
            return nil
        }
        return FrontmostApp(
            bundleID: bundleID,
            displayName: active.displayName ?? bundleID
        )
    }
}
