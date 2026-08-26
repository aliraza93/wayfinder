import Foundation

/// Mirrors `NSApplication.ActivationPolicy` without requiring AppKit in tests.
public enum AppActivationPolicy: Equatable, Sendable {
    case regular
    case accessory
    case prohibited
    case other
}

/// Snapshot of a running process for enumeration / filtering.
/// Bundle id identifies "an app," not a window.
public struct RunningAppInfo: Equatable, Sendable {
    public var bundleID: String?
    public var displayName: String?
    public var activationPolicy: AppActivationPolicy
    /// True when this process is the frontmost application.
    public var isActive: Bool
    public var processID: Int32?

    public init(
        bundleID: String?,
        displayName: String?,
        activationPolicy: AppActivationPolicy,
        isActive: Bool,
        processID: Int32? = nil
    ) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.activationPolicy = activationPolicy
        self.isActive = isActive
        self.processID = processID
    }
}

/// Injected source of running apps. Production uses `NSWorkspace`; tests inject fakes.
public protocol RunningAppsProvider: Sendable {
    func runningApps() -> [RunningAppInfo]
}
