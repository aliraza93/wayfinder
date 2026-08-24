import AppKit
import Foundation

/// Ensures only one Waypoint process runs for `com.twixrsolutions.waypoint`.
/// A new launch (e.g. Xcode Run) terminates older instances so you never get two menu-bar icons.
enum SingleInstance {
    static func claim() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.twixrsolutions.waypoint"
        let myPID = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            where app.processIdentifier != myPID
        {
            _ = app.terminate()
        }
    }
}
