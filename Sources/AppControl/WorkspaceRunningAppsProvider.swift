import AppKit
import Foundation

/// Live `NSWorkspace` / `NSRunningApplication` provider. Does not activate anything.
public struct WorkspaceRunningAppsProvider: RunningAppsProvider {
    public init() {}

    public func runningApps() -> [RunningAppInfo] {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return NSWorkspace.shared.runningApplications.map { app in
            RunningAppInfo(
                bundleID: app.bundleIdentifier,
                displayName: app.localizedName,
                activationPolicy: Self.mapPolicy(app.activationPolicy),
                isActive: frontmostPID.map { $0 == app.processIdentifier } ?? app.isActive,
                processID: app.processIdentifier
            )
        }
    }

    private static func mapPolicy(_ policy: NSApplication.ActivationPolicy) -> AppActivationPolicy {
        switch policy {
        case .regular: return .regular
        case .accessory: return .accessory
        case .prohibited: return .prohibited
        @unknown default: return .other
        }
    }
}
