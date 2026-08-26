import Domain
import Foundation
import WaypointAccessibility

/// Read-only workspace scanner. Discovers apps/windows/targets — never activates or emits input.
public struct WorkspaceScanner: Sendable {
    private let enumerator: AppEnumerator
    private let windowEnumerator: WindowTitleEnumerator

    public init(
        enumerator: AppEnumerator = AppEnumerator(),
        windowEnumerator: WindowTitleEnumerator = WindowTitleEnumerator()
    ) {
        self.enumerator = enumerator
        self.windowEnumerator = windowEnumerator
    }

    /// Scan currently visible user-facing apps. Does not start automation.
    public func scan() -> WorkspaceDiscoverySnapshot {
        let running = enumerator.userFacingApps()
        var details: [DiscoveredAppDetail] = []

        for app in running {
            guard let bundleID = app.bundleID, !bundleID.isEmpty else { continue }
            if NavigationAppPolicy.isForbidden(bundleID) { continue }
            if bundleID == ProductIdentity.bundleIdentifier { continue }

            let classification = ApplicationClassifier.classify(bundleID: bundleID)
            let name = app.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = (name?.isEmpty == false) ? name! : bundleID
            let pid = app.processID ?? 0

            let (axStatus, windows): (DiscoveryAccessibilityStatus, [DiscoveredWindowInfo])
            if pid != 0 {
                (axStatus, windows) = windowEnumerator.windows(processID: pid)
            } else {
                (axStatus, windows) = (.unavailable, [])
            }

            // Prefer apps that have at least one titled window (visible work).
            // Still include prioritized apps even with empty windows so Cursor/Chrome show up.
            let prioritized = WorkspaceDiscoveryPlanner.priority(
                bundleID: bundleID,
                classification: classification
            ) <= 6
            if windows.isEmpty, !prioritized, !app.isActive {
                continue
            }

            let targets = WorkspaceDiscoveryPlanner.discoverTargets(
                displayName: displayName,
                bundleID: bundleID,
                processID: pid,
                classification: classification,
                accessibilityStatus: axStatus,
                windows: windows
            )

            details.append(
                DiscoveredAppDetail(
                    displayName: displayName,
                    bundleID: bundleID,
                    processID: pid,
                    classification: classification,
                    isActive: app.isActive,
                    accessibilityStatus: axStatus,
                    windows: windows,
                    targets: targets
                )
            )
        }

        return WorkspaceDiscoverySnapshot(
            scannedAt: Date(),
            apps: WorkspaceDiscoveryPlanner.sortApps(details)
        )
    }
}
