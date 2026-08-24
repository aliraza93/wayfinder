import Domain
import Foundation

/// Discovers user-facing running apps suitable for universal navigation (no deep AX tree).
public struct ApplicationDiscovery: Sendable {
    private let enumerator: AppEnumerator

    public init(enumerator: AppEnumerator = AppEnumerator()) {
        self.enumerator = enumerator
    }

    /// Running `.regular` apps with classification heuristics. Excludes Waypoint.
    public func discover() -> [DiscoveredApplication] {
        enumerator.userFacingApps().compactMap { app in
            guard let bundleID = app.bundleID, !bundleID.isEmpty else { return nil }
            if bundleID == "com.twixrsolutions.waypoint" { return nil }
            let name = app.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return DiscoveredApplication(
                bundleID: bundleID,
                displayName: (name?.isEmpty == false) ? name! : bundleID,
                classification: ApplicationClassifier.classify(bundleID: bundleID),
                isActive: app.isActive
            )
        }
    }

    public func discover(matching scope: DiscoveryScope) -> [DiscoveredApplication] {
        discover().filter { scope.allows($0.classification, bundleID: $0.bundleID) }
    }
}

/// Production `ApplicationDiscoverySource` for the universal engine.
public struct LiveApplicationDiscoverySource: ApplicationDiscoverySource {
    private let discovery: ApplicationDiscovery

    public init(discovery: ApplicationDiscovery = ApplicationDiscovery()) {
        self.discovery = discovery
    }

    public func discoverApplications() -> [DiscoveredApplication] {
        discovery.discover()
    }
}
