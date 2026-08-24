import AppKit
import Foundation

/// Brings a target app frontmost — launches it if needed so Chrome/Cursor workflows can start cold.
public struct AppActivator: Sendable {
    public init() {}

    /// Returns `true` if an instance of `bundleID` was activated (must already be running).
    @discardableResult
    public func activate(bundleID: String) -> Bool {
        let matches = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID
        }
        guard let app = matches.first(where: { $0.activationPolicy == .regular }) ?? matches.first else {
            return false
        }
        return app.activate(options: [.activateIgnoringOtherApps])
    }

    /// `true` when the bundle is installed (running or not).
    public func isInstalled(bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
            || !NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }.isEmpty
    }

    public func isRunning(bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    /// Activates a running app, or launches it then waits until frontmost.
    public func activateOrLaunch(bundleID: String, timeoutSeconds: TimeInterval = 8.0) async -> Bool {
        if activate(bundleID: bundleID) {
            return await waitUntilFrontmost(bundleID: bundleID, timeoutSeconds: min(timeoutSeconds, 3.0))
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        } catch {
            return false
        }

        return await waitUntilFrontmost(bundleID: bundleID, timeoutSeconds: timeoutSeconds)
    }

    /// Activates `bundleID` and waits until it is frontmost (or timeout). Does not launch.
    public func activateAndWait(bundleID: String, timeoutSeconds: TimeInterval = 2.0) async -> Bool {
        guard activate(bundleID: bundleID) else { return false }
        return await waitUntilFrontmost(bundleID: bundleID, timeoutSeconds: timeoutSeconds)
    }

    public func isFrontmost(bundleID: String) -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    private func waitUntilFrontmost(bundleID: String, timeoutSeconds: TimeInterval) async -> Bool {
        if isFrontmost(bundleID: bundleID) { return true }
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
            // Keep nudging activation while waiting (launch can race focus).
            _ = activate(bundleID: bundleID)
            if isFrontmost(bundleID: bundleID) { return true }
        }
        return isFrontmost(bundleID: bundleID)
    }
}
