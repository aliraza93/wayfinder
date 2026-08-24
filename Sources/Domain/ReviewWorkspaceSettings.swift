import Foundation

/// Default single workflow name for the cohesive read/review session.
public enum ReadAndReviewWorkspace {
    public static let workflowName = "Read & Review Workspace"
}

/// How configured files/tabs are ordered across a session.
public enum ReviewTargetOrder: String, Equatable, Sendable, CaseIterable {
    case sequential
    case random

    public var title: String {
        switch self {
        case .sequential: return "Sequential"
        case .random: return "Random order"
        }
    }
}

/// Fixed navigation pacing (not for imitating human activity).
public enum NavigationSpeedPreset: String, Equatable, Sendable, CaseIterable, Identifiable {
    case slow
    case normal
    case fast
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .slow: return "Slow"
        case .normal: return "Normal"
        case .fast: return "Fast"
        case .custom: return "Custom"
        }
    }

    /// Default interval between navigation actions for this preset (seconds).
    public var defaultIntervalSeconds: Double {
        switch self {
        case .slow: return 0.85
        case .normal: return 0.35
        case .fast: return 0.12
        case .custom: return 0.35
        }
    }
}

/// User-configured read/review session (one workflow drives all files + tabs).
public struct ReviewWorkspaceSettings: Equatable, Sendable {
    /// Absolute or `~`-expanded workspace root for relative file paths.
    public var workspacePath: String
    /// Paths relative to workspace (or absolute). Opened read-only via AppKit.
    public var filePaths: [String]
    /// Labels for configured Chrome tabs (identity for UI/logs; switching uses tab cycle).
    public var chromeTabLabels: [String]
    public var dwellMinSeconds: Double
    public var dwellMaxSeconds: Double
    public var speed: NavigationSpeedPreset
    public var customIntervalSeconds: Double
    public var targetOrder: ReviewTargetOrder
    /// After the last target, start again until session duration ends.
    public var loopTargets: Bool

    public init(
        workspacePath: String = "",
        filePaths: [String] = [],
        chromeTabLabels: [String] = [],
        dwellMinSeconds: Double = 30,
        dwellMaxSeconds: Double = 180,
        speed: NavigationSpeedPreset = .normal,
        customIntervalSeconds: Double = 0.35,
        targetOrder: ReviewTargetOrder = .sequential,
        loopTargets: Bool = true
    ) {
        self.workspacePath = workspacePath
        self.filePaths = filePaths
        self.chromeTabLabels = chromeTabLabels
        self.dwellMinSeconds = dwellMinSeconds
        self.dwellMaxSeconds = dwellMaxSeconds
        self.speed = speed
        self.customIntervalSeconds = customIntervalSeconds
        self.targetOrder = targetOrder
        self.loopTargets = loopTargets
    }

    public static let `default` = ReviewWorkspaceSettings()

    /// Clamps dwell range and ensures `min < max`.
    public mutating func normalize() {
        dwellMinSeconds = min(max(5, dwellMinSeconds), 600)
        dwellMaxSeconds = min(max(10, dwellMaxSeconds), 900)
        if dwellMinSeconds >= dwellMaxSeconds {
            dwellMaxSeconds = dwellMinSeconds + 1
        }
        customIntervalSeconds = min(max(0.05, customIntervalSeconds), 5.0)
        filePaths = filePaths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        chromeTabLabels = chromeTabLabels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        workspacePath = workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func validated() -> (ok: Bool, message: String?) {
        var copy = self
        copy.normalize()
        if copy.dwellMinSeconds >= copy.dwellMaxSeconds {
            return (false, "dwell minimum must be less than maximum")
        }
        return (true, nil)
    }

    public var actionIntervalSeconds: Double {
        switch speed {
        case .slow, .normal, .fast:
            return speed.defaultIntervalSeconds
        case .custom:
            return customIntervalSeconds
        }
    }

    public func randomDwellSeconds() -> Double {
        Double.random(in: dwellMinSeconds...dwellMaxSeconds)
    }

    /// Resolve a configured file against the workspace root.
    public func resolvedFilePath(_ relativeOrAbsolute: String) -> String {
        let trimmed = relativeOrAbsolute.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            return (trimmed as NSString).expandingTildeInPath
        }
        let root = (workspacePath as NSString).expandingTildeInPath
        if root.isEmpty { return trimmed }
        return (root as NSString).appendingPathComponent(trimmed)
    }
}

/// One configured surface in the Read & Review queue.
public enum ReviewTarget: Equatable, Sendable {
    case editorFile(path: String, displayName: String)
    case chromeTab(label: String, index: Int)

    public var identity: String {
        switch self {
        case .editorFile(_, let displayName): return displayName
        case .chromeTab(let label, _): return label
        }
    }

    public var kindLabel: String {
        switch self {
        case .editorFile: return "file"
        case .chromeTab: return "tab"
        }
    }
}
