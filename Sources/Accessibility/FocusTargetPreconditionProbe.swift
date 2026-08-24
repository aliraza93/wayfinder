import CoreEngine
import Domain
import Foundation

/// Verifies the target is still running and frontmost before emit.
///
/// Does **not** require `focusedWindowExists()` — Electron apps (Cursor, VS Code)
/// often omit a focused AX window even when clearly frontmost and usable.
public struct FocusTargetPreconditionProbe: RunPreconditionProbe {
    private let probe: any AXProbe
    private let isRunning: @Sendable (String) -> Bool

    public init(probe: any AXProbe, isRunning: @escaping @Sendable (String) -> Bool) {
        self.probe = probe
        self.isRunning = isRunning
    }

    public func assertReady(for target: TargetApp) async throws {
        guard isRunning(target.bundleID) else {
            throw PreconditionError("target app not running")
        }
        guard let front = probe.frontmostAppBundleID(), front == target.bundleID else {
            throw PreconditionError("target is not frontmost")
        }
    }
}
