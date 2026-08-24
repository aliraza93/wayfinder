import Foundation

/// Preset wall-clock durations for long-running navigation workflows.
public enum RunDurationPreset: String, CaseIterable, Identifiable, Sendable {
    case oneMinute
    case fiveMinutes
    case tenMinutes
    case thirtyMinutes
    case oneHour
    case custom
    case untilStopped
    case iterationsOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .oneMinute: return "1 minute"
        case .fiveMinutes: return "5 minutes"
        case .tenMinutes: return "10 minutes"
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        case .custom: return "Custom minutes"
        case .untilStopped: return "Until stopped"
        case .iterationsOnly: return "Advanced: fixed steps"
        }
    }

    /// Duration-only presets shown in the simple editor.
    public static var timedOnly: [RunDurationPreset] {
        [.oneMinute, .fiveMinutes, .tenMinutes, .thirtyMinutes, .oneHour, .custom]
    }

    public var isTimedReview: Bool {
        switch self {
        case .oneMinute, .fiveMinutes, .tenMinutes, .thirtyMinutes, .oneHour, .custom, .untilStopped:
            return true
        case .iterationsOnly:
            return false
        }
    }

    public var seconds: Double? {
        switch self {
        case .oneMinute: return 60
        case .fiveMinutes: return 300
        case .tenMinutes: return 600
        case .thirtyMinutes: return 1_800
        case .oneHour: return 3_600
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
        case 60: return .oneMinute
        case 300: return .fiveMinutes
        case 600: return .tenMinutes
        case 1_800: return .thirtyMinutes
        case 3_600: return .oneHour
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
