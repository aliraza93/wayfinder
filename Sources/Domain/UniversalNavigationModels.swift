import Foundation

/// Lifecycle of one navigation surface in the universal workflow.
public enum NavigationTargetLifecycle: String, Equatable, Sendable, Codable, CaseIterable {
    case discovered
    case approved
    case pending
    case active
    case completed
    case skipped
    case failed

    public var title: String {
        switch self {
        case .discovered: return "Discovered"
        case .approved: return "Approved"
        case .pending: return "Pending"
        case .active: return "Active"
        case .completed: return "Completed"
        case .skipped: return "Skipped"
        case .failed: return "Failed"
        }
    }
}

/// One entry in the universal navigation history (identity metadata only — never body text).
public struct NavigationHistoryEntry: Equatable, Sendable, Identifiable {
    public var id: String
    public var identityKey: String
    public var displayName: String
    public var lifecycle: NavigationTargetLifecycle
    public var at: Date

    public init(
        id: String = UUID().uuidString,
        identityKey: String,
        displayName: String,
        lifecycle: NavigationTargetLifecycle,
        at: Date = Date()
    ) {
        self.id = id
        self.identityKey = identityKey
        self.displayName = displayName
        self.lifecycle = lifecycle
        self.at = at
    }
}

/// Ordered log of target lifecycle transitions for the current session.
public struct NavigationHistory: Equatable, Sendable {
    public private(set) var entries: [NavigationHistoryEntry]
    public var maxEntries: Int

    public init(entries: [NavigationHistoryEntry] = [], maxEntries: Int = 200) {
        self.entries = entries
        self.maxEntries = max(20, maxEntries)
    }

    public mutating func record(
        identityKey: String,
        displayName: String,
        lifecycle: NavigationTargetLifecycle,
        at: Date = Date()
    ) {
        entries.append(
            NavigationHistoryEntry(
                identityKey: identityKey,
                displayName: displayName,
                lifecycle: lifecycle,
                at: at
            )
        )
        if entries.count > maxEntries {
            entries = Array(entries.suffix(maxEntries))
        }
    }

    public var recentDisplayNames: [String] {
        entries.suffix(12).map(\.displayName)
    }

    public func countsByLifecycle() -> [NavigationTargetLifecycle: Int] {
        var counts: [NavigationTargetLifecycle: Int] = [:]
        for entry in entries {
            counts[entry.lifecycle, default: 0] += 1
        }
        return counts
    }
}

/// Tracks how often each target identity has been visited this session.
/// Used for rotation so the planner avoids hammering the same surface.
public struct VisitedTargetTracker: Equatable, Sendable {
    public private(set) var visitCounts: [String: Int]
    public private(set) var lastVisitedAt: [String: Date]
    public private(set) var lifecycleByKey: [String: NavigationTargetLifecycle]

    public init(
        visitCounts: [String: Int] = [:],
        lastVisitedAt: [String: Date] = [:],
        lifecycleByKey: [String: NavigationTargetLifecycle] = [:]
    ) {
        self.visitCounts = visitCounts
        self.lastVisitedAt = lastVisitedAt
        self.lifecycleByKey = lifecycleByKey
    }

    public static let empty = VisitedTargetTracker()

    public func visitCount(for key: String) -> Int {
        visitCounts[key] ?? 0
    }

    public func lifecycle(for key: String) -> NavigationTargetLifecycle {
        lifecycleByKey[key] ?? .discovered
    }

    public mutating func setLifecycle(_ lifecycle: NavigationTargetLifecycle, for key: String) {
        lifecycleByKey[key] = lifecycle
    }

    public mutating func markPending(_ key: String) {
        if lifecycleByKey[key] == nil || lifecycleByKey[key] == .discovered {
            lifecycleByKey[key] = .pending
        }
    }

    public mutating func markActive(_ key: String, at: Date = Date()) {
        lifecycleByKey[key] = .active
        lastVisitedAt[key] = at
    }

    public mutating func markCompleted(_ key: String, at: Date = Date()) {
        lifecycleByKey[key] = .completed
        visitCounts[key, default: 0] += 1
        lastVisitedAt[key] = at
    }

    public mutating func markSkipped(_ key: String) {
        lifecycleByKey[key] = .skipped
    }

    public mutating func markFailed(_ key: String) {
        lifecycleByKey[key] = .failed
    }

    public mutating func markApproved(_ key: String) {
        lifecycleByKey[key] = .approved
    }

    public func hasVisited(_ key: String) -> Bool {
        (visitCounts[key] ?? 0) > 0
    }
}

/// Product alias — same type as `ReviewTargetSelector`.
public typealias TargetSelector = ReviewTargetSelector

/// Pure helpers bridging discovery approvals into a Universal Workspace workflow.
public enum UniversalWorkflowBridge: Sendable {
    /// Defaults for the single Universal Workspace Navigation workflow.
    public static var defaultSettings: ReviewWorkspaceSettings {
        var settings = ReviewWorkspaceSettings(
            dwellMinSeconds: 30,
            dwellMaxSeconds: 180,
            pacing: .relaxed,
            targetOrder: .applicationPriority,
            loopTargets: true,
            discoverRunningApps: true,
            discovery: DiscoveryScope(
                includeEditors: true,
                includeBrowsers: true,
                includeFinder: true,
                includePreview: true,
                includeOther: false
            ),
            refreshTargetsBetweenDwells: true,
            chrome: .default
        )
        settings.normalize()
        return settings
    }

    public static func applyUniversalRuntimeFlags(_ settings: inout ReviewWorkspaceSettings) {
        settings.discoverRunningApps = true
        settings.refreshTargetsBetweenDwells = true
        if !settings.discovery.includeFinder {
            settings.discovery.includeFinder = true
        }
        if !settings.discovery.includePreview {
            settings.discovery.includePreview = true
        }
        settings.normalize()
    }

    /// Merges approved discovery targets into a workflow (apps / files / tabs). Does not start a run.
    public static func mergeApprovedTargets(
        into workflow: inout Workflow,
        approved: [NavigationTarget]
    ) {
        applyUniversalRuntimeFlags(&workflow.review)
        let existingBundleIDs = Set(workflow.targets.map(\.bundleID))

        for target in approved where target.kind == .application {
            if existingBundleIDs.contains(target.bundleID) { continue }
            if NavigationAppPolicy.isForbidden(target.bundleID) { continue }
            workflow.targets.append(
                TargetApp(bundleID: target.bundleID, classification: target.classification)
            )
        }

        for target in approved where target.kind == .file {
            let path = (target.identityPath ?? target.displayName)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { continue }
            if !workflow.review.filePaths.contains(path) {
                workflow.review.filePaths.append(path)
            }
            if !workflow.reviewFilePaths.contains(path) {
                workflow.reviewFilePaths.append(path)
            }
        }

        for target in approved where target.kind == .tab {
            let label = target.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { continue }
            if !workflow.review.chromeTabLabels.contains(label) {
                workflow.review.chromeTabLabels.append(label)
            }
        }

        workflow.review.normalize()
        if workflow.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            workflow.name = UniversalWorkspaceNavigation.workflowName
        }
    }
}
