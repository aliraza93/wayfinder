import AppKit
import Foundation

/// Brings a running app frontmost so focus-guarded navigation can proceed.
public struct AppActivator: Sendable {
    public init() {}

    /// Returns `true` if an instance of `bundleID` was activated.
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
}
