import Foundation

/// Three content-free Accessibility queries. Nothing more — no document tree traversal.
public struct CoarseAX: Sendable {
    private let probe: any AXProbe

    public init(probe: any AXProbe = SystemAXProbe()) {
        self.probe = probe
    }

    public func frontmostAppBundleID() -> String? {
        probe.frontmostAppBundleID()
    }

    public func focusedWindowExists() -> Bool {
        probe.focusedWindowExists()
    }

    public func focusedElementBundleID() -> String? {
        probe.focusedElementBundleID()
    }
}
