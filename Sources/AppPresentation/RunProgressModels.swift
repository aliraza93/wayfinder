import Foundation

/// Preset wall-clock durations for long-running navigation workflows.
public enum RunDurationPreset: String, CaseIterable, Identifiable, Sendable {
    case oneHour
    case twoHours
    case fourHours
    case eightHours
    case custom
    case untilStopped
    case iterationsOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .oneHour: return "1 hour"
        case .twoHours: return "2 hours"
        case .fourHours: return "4 hours"
        case .eightHours: return "8 hours"
        case .custom: return "Custom hours"
        case .untilStopped: return "Until stopped"
        case .iterationsOnly: return "Advanced: fixed steps"
        }
    }

    /// Duration-only presets shown in the simple editor.
    public static var timedOnly: [RunDurationPreset] {
        [.oneHour, .twoHours, .fourHours, .eightHours, .custom]
    }

    public var isTimedReview: Bool {
        switch self {
        case .oneHour, .twoHours, .fourHours, .eightHours, .custom, .untilStopped:
            return true
        case .iterationsOnly:
            return false
        }
    }

    public var seconds: Double? {
        switch self {
        case .oneHour: return 3_600
        case .twoHours: return 7_200
        case .fourHours: return 14_400
        case .eightHours: return 28_800
        case .custom, .untilStopped, .iterationsOnly: return nil
        }
    }

    public static func infer(
        maxDurationSeconds: Double?,
        untilStopped: Bool,
        loopEnabled: Bool
    ) -> RunDurationPreset {
        if untilStopped { return .untilStopped }
        guard let seconds = maxDurationSeconds else {
            return loopEnabled ? .iterationsOnly : .iterationsOnly
        }
        switch Int(seconds.rounded()) {
        case 3_600: return .oneHour
        case 7_200: return .twoHours
        case 14_400: return .fourHours
        case 28_800: return .eightHours
        default: return .custom
        }
    }
}

/// Explicit run lifecycle shown in the menu / progress UI.
public enum RunUIPhase: String, Equatable, Sendable {
    case idle
    case running
    case paused
    case completed
    case stopped
    case failed

    public var title: String {
        switch self {
        case .idle: return "Idle"
        case .running: return "Running"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .stopped: return "Stopped"
        case .failed: return "Failed"
        }
    }
}
