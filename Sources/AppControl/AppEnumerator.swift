import Domain
import Foundation

/// Enumerates user-facing running apps (`.regular` only). No activation.
public struct AppEnumerator: Sendable {
    private let provider: any RunningAppsProvider

    public init(provider: any RunningAppsProvider = WorkspaceRunningAppsProvider()) {
        self.provider = provider
    }

    /// Running apps with `.regular` activation policy and a non-empty bundle id.
    /// Drops helpers, agents, and accessory/prohibited processes.
    public func userFacingApps() -> [RunningAppInfo] {
        Self.filterUserFacing(provider.runningApps())
    }

    /// Pure filtering — unit-tested with injected lists.
    public static func filterUserFacing(_ apps: [RunningAppInfo]) -> [RunningAppInfo] {
        apps.filter { app in
            app.activationPolicy == .regular
                && !(app.bundleID ?? "").isEmpty
        }
    }

    /// Whether any running `.regular` app matches the bundle id.
    public func isRunning(bundleID: String) -> Bool {
        userFacingApps().contains { $0.bundleID == bundleID }
    }

    /// Resolve a `TargetApp` to a currently running user-facing process, if any.
    public func resolve(_ target: TargetApp) -> RunningAppInfo? {
        userFacingApps().first { $0.bundleID == target.bundleID }
    }
}
