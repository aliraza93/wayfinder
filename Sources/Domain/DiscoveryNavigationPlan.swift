import Foundation

/// One step in the Scan → Review → Preview plan (identity only — never body text).
public struct DiscoveryPlanStep: Equatable, Sendable, Identifiable {
    public var id: String
    public var index: Int
    public var appName: String
    public var targetName: String
    public var kind: NavigationTargetKind
    public var bundleID: String

    public init(
        id: String = UUID().uuidString,
        index: Int,
        appName: String,
        targetName: String,
        kind: NavigationTargetKind,
        bundleID: String
    ) {
        self.id = id
        self.index = index
        self.appName = appName
        self.targetName = targetName
        self.kind = kind
        self.bundleID = bundleID
    }

    public var displayLine: String {
        "\(appName) → \(targetName)"
    }
}

/// Estimated reading session length from approved targets + dwell range (not for deception).
public struct DiscoverySessionEstimate: Equatable, Sendable {
    public var approvedCount: Int
    public var estimatedSeconds: Double
    public var durationCapSeconds: Double?
    public var untilStopped: Bool

    public init(
        approvedCount: Int,
        estimatedSeconds: Double,
        durationCapSeconds: Double? = nil,
        untilStopped: Bool = false
    ) {
        self.approvedCount = approvedCount
        self.estimatedSeconds = estimatedSeconds
        self.durationCapSeconds = durationCapSeconds
        self.untilStopped = untilStopped
    }

    public var formattedDuration: String {
        if untilStopped, durationCapSeconds == nil {
            let reading = Self.formatMinutes(estimatedSeconds)
            return "until stopped (~\(reading) of reading)"
        }
        return Self.formatMinutes(estimatedSeconds)
    }

    public static func formatMinutes(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total) seconds" }
        let minutes = Int((Double(total) / 60.0).rounded())
        if minutes == 1 { return "1 minute" }
        return "\(minutes) minutes"
    }
}

/// Pure helpers for the Scan → Review → Preview → Start discovery flow.
public enum DiscoveryNavigationPlan: Sendable {
    /// Surface kinds shown in Review (includes windows).
    public static let reviewKinds: [NavigationTargetKind] = [
        .application,
        .window,
        .file,
        .tab,
        .document,
        .navigation,
    ]

    public static func reviewTitle(for kind: NavigationTargetKind) -> String {
        switch kind {
        case .application: return "Applications"
        case .window: return "Windows"
        case .file: return "Files"
        case .tab: return "Tabs / websites"
        case .document: return "Documents"
        case .navigation: return "Navigation / directories"
        }
    }

    /// Build an ordered preview from approved targets (no automation).
    public static func buildPlan(from snapshot: WorkspaceDiscoverySnapshot) -> [DiscoveryPlanStep] {
        let apps = WorkspaceDiscoveryPlanner.sortApps(snapshot.apps)
        var steps: [DiscoveryPlanStep] = []
        var index = 1

        for app in apps {
            let approved = app.targets.filter(\.approved)
            guard !approved.isEmpty else { continue }

            let surfaces = approved
                .filter { $0.kind != .application }
                .sorted { kindRank($0.kind) < kindRank($1.kind) }

            if surfaces.isEmpty {
                steps.append(
                    DiscoveryPlanStep(
                        index: index,
                        appName: app.displayName,
                        targetName: app.displayName,
                        kind: .application,
                        bundleID: app.bundleID
                    )
                )
                index += 1
            } else {
                for target in surfaces {
                    steps.append(
                        DiscoveryPlanStep(
                            index: index,
                            appName: app.displayName,
                            targetName: target.displayName,
                            kind: target.kind,
                            bundleID: app.bundleID
                        )
                    )
                    index += 1
                }
            }
        }
        return steps
    }

    public static func estimate(
        approvedCount: Int,
        dwellMinSeconds: Double,
        dwellMaxSeconds: Double,
        maxDurationSeconds: Double?,
        untilStopped: Bool
    ) -> DiscoverySessionEstimate {
        let lo = max(5, dwellMinSeconds)
        let hi = max(lo + 1, dwellMaxSeconds)
        let averageDwell = (lo + hi) / 2
        let reading = Double(max(0, approvedCount)) * averageDwell
        if untilStopped {
            return DiscoverySessionEstimate(
                approvedCount: approvedCount,
                estimatedSeconds: reading,
                durationCapSeconds: nil,
                untilStopped: true
            )
        }
        if let cap = maxDurationSeconds {
            return DiscoverySessionEstimate(
                approvedCount: approvedCount,
                estimatedSeconds: min(reading, cap),
                durationCapSeconds: cap,
                untilStopped: false
            )
        }
        return DiscoverySessionEstimate(
            approvedCount: approvedCount,
            estimatedSeconds: reading,
            durationCapSeconds: nil,
            untilStopped: false
        )
    }

    public static func appTargetCounts(from snapshot: WorkspaceDiscoverySnapshot) -> [(name: String, count: Int)] {
        WorkspaceDiscoveryPlanner.sortApps(snapshot.apps).compactMap { app in
            let count = app.targets.filter(\.approved).count
            guard count > 0 else { return nil }
            return (app.displayName, count)
        }
    }

    private static func kindRank(_ kind: NavigationTargetKind) -> Int {
        switch kind {
        case .file: return 0
        case .tab: return 1
        case .document: return 2
        case .window: return 3
        case .navigation: return 4
        case .application: return 5
        }
    }
}

extension WorkspaceDiscoverySnapshot {
    public var foundCountsByKind: [(kind: NavigationTargetKind, count: Int)] {
        DiscoveryNavigationPlan.reviewKinds.compactMap { kind in
            let count = targets(ofKind: kind).count
            guard count > 0 else { return nil }
            return (kind, count)
        }
    }

    public mutating func setAppApproved(bundleID: String, approved: Bool) {
        for ai in apps.indices where apps[ai].bundleID == bundleID {
            for ti in apps[ai].targets.indices {
                apps[ai].targets[ti].approved = approved
            }
        }
    }

    public mutating func setKindApproved(_ kind: NavigationTargetKind, approved: Bool) {
        for ai in apps.indices {
            for ti in apps[ai].targets.indices where apps[ai].targets[ti].kind == kind {
                apps[ai].targets[ti].approved = approved
            }
        }
    }
}
