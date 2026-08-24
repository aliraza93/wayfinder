import Domain
import Foundation
import Observability
import Permissions

/// Permission onboarding state machine (view-model only).
public final class OnboardingViewModel: @unchecked Sendable {
    public private(set) var state: PermissionState
    public private(set) var didPrompt = false
    public var showsOnboarding: Bool {
        state != .granted
    }

    private let refreshState: () -> PermissionState
    private let requestAccess: () -> PermissionState
    private let openSettings: () -> Void

    public init(
        initial: PermissionState = .unknown,
        refreshState: @escaping () -> PermissionState,
        requestAccess: @escaping () -> PermissionState,
        openSettings: @escaping () -> Void
    ) {
        self.state = initial
        self.refreshState = refreshState
        self.requestAccess = requestAccess
        self.openSettings = openSettings
    }

    public func refresh() {
        state = refreshState()
    }

    public func request() {
        state = requestAccess()
        didPrompt = true
    }

    public func openAccessibilitySettings() {
        openSettings()
        state = refreshState()
    }

    public var statusTitle: String {
        switch state {
        case .unknown: return "Checking Accessibility…"
        case .denied: return "Accessibility required"
        case .granted: return "Accessibility granted"
        }
    }

    public var statusDetail: String {
        switch state {
        case .unknown:
            return HonestCopy.permissionWhy
        case .denied:
            return """
            Enable Waypoint in System Settings → Privacy & Security → Accessibility, then return here.

            If the toggle is already ON but this app still says Denied, the grant is for an old build \
            signature: select Waypoint in that list, click − to remove it, Quit Waypoint, Run again from \
            Xcode, then enable the new Waypoint entry.
            """
        case .granted:
            return "You’re ready to build and run read-only navigation workflows."
        }
    }
}

/// Live run status for the menu bar (updated on main by the session controller).
public struct RunLiveStatus: Equatable, Sendable {
    public var workflowName: String
    public var phase: RunUIPhase
    public var currentStepLabel: String
    public var nextStepLabel: String
    public var elapsedSeconds: Double
    public var durationSeconds: Double?
    public var remainingSeconds: Double?
    public var eventCount: Int
    public var scrollActionCount: Int
    public var keyboardActionCount: Int

    public var isRunning: Bool {
        phase == .running || phase == .paused
    }

    public init(
        workflowName: String = "",
        phase: RunUIPhase = .idle,
        currentStepLabel: String = "—",
        nextStepLabel: String = "—",
        elapsedSeconds: Double = 0,
        durationSeconds: Double? = nil,
        remainingSeconds: Double? = nil,
        eventCount: Int = 0,
        scrollActionCount: Int = 0,
        keyboardActionCount: Int = 0
    ) {
        self.workflowName = workflowName
        self.phase = phase
        self.currentStepLabel = currentStepLabel
        self.nextStepLabel = nextStepLabel
        self.elapsedSeconds = elapsedSeconds
        self.durationSeconds = durationSeconds
        self.remainingSeconds = remainingSeconds
        self.eventCount = eventCount
        self.scrollActionCount = scrollActionCount
        self.keyboardActionCount = keyboardActionCount
    }

    public var summaryLine: String {
        switch phase {
        case .running, .paused:
            var lines = ["\(phase.title)"]
            if let durationSeconds {
                lines.append("Duration: \(Self.formatClock(durationSeconds))")
            } else if phase == .running || phase == .paused {
                lines.append("Duration: until stopped")
            }
            lines.append("Elapsed: \(Self.formatClock(elapsedSeconds))")
            if let remainingSeconds {
                lines.append("Remaining: \(Self.formatClock(remainingSeconds))")
            }
            lines.append("Current: \(currentStepLabel)")
            lines.append("Scroll: \(scrollActionCount)  Keys: \(keyboardActionCount)")
            return lines.joined(separator: " · ")
        case .idle:
            if workflowName.isEmpty { return "Idle" }
            return "Last: \(workflowName) (\(eventCount) events)"
        case .completed, .stopped, .failed:
            return "\(phase.title): \(workflowName) (\(eventCount) events)"
        }
    }

    public static func formatClock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    public static func counts(from events: [RunEvent]) -> (scroll: Int, keyboard: Int) {
        var scroll = 0
        var keyboard = 0
        for event in events where event.result == .completed {
            switch event.actionKind {
            case "scroll":
                scroll += 1
            case "pageNavigate", "arrowNavigate":
                keyboard += 1
            default:
                break
            }
        }
        return (scroll, keyboard)
    }
}

/// Timeline backed by content-free `RunRecorder` snapshots.
public final class TimelineViewModel: @unchecked Sendable {
    public private(set) var rows: [TimelineRow] = []

    public struct TimelineRow: Equatable, Sendable, Identifiable {
        public var id: String
        public var timestamp: Date
        public var actionKind: String
        public var targetBundleID: String
        public var result: String

        public init(id: String, timestamp: Date, actionKind: String, targetBundleID: String, result: String) {
            self.id = id
            self.timestamp = timestamp
            self.actionKind = actionKind
            self.targetBundleID = targetBundleID
            self.result = result
        }
    }

    public init() {}

    public func replace(with events: [RunEvent]) {
        rows = events.enumerated().map { index, event in
            TimelineRow(
                id: "\(event.timestamp.timeIntervalSince1970)-\(index)",
                timestamp: event.timestamp,
                actionKind: event.actionKind,
                targetBundleID: event.targetBundleID,
                result: event.result.rawValue
            )
        }
    }

    public func append(from recorder: RunRecorder) {
        replace(with: recorder.snapshot())
    }
}

/// Picks which workflow to run and tracks live status labels from step index.
public final class RunSessionViewModel: @unchecked Sendable {
    public private(set) var workflowNames: [String] = []
    public var selectedName: String?
    public private(set) var live = RunLiveStatus()
    public private(set) var canStart: Bool = false

    private var accessibilityGranted = false
    private var isRunning = false
    private var configuredDuration: Double?

    public init() {}

    public func updateAccessibilityGranted(_ granted: Bool) {
        accessibilityGranted = granted
        recomputeCanStart()
    }

    public func updateNames(_ names: [String]) {
        workflowNames = names
        if selectedName == nil || !(names.contains(selectedName ?? "")) {
            selectedName = names.first
        }
        recomputeCanStart()
    }

    public func select(_ name: String) {
        selectedName = name
        recomputeCanStart()
    }

    public func markRunning(workflowName: String, steps: [Step], durationSeconds: Double?) {
        isRunning = true
        configuredDuration = durationSeconds
        live = RunLiveStatus(
            workflowName: workflowName,
            phase: .running,
            currentStepLabel: Self.label(for: steps.first?.action),
            nextStepLabel: Self.label(for: steps.dropFirst().first?.action),
            elapsedSeconds: 0,
            durationSeconds: durationSeconds,
            remainingSeconds: durationSeconds,
            eventCount: 0
        )
        recomputeCanStart()
    }

    public func markPaused() {
        guard isRunning else { return }
        var next = live
        next.phase = .paused
        live = next
    }

    public func markResumed() {
        guard isRunning else { return }
        var next = live
        next.phase = .running
        live = next
    }

    public func updateProgress(
        stepIndex: Int,
        steps: [Step],
        elapsed: Double,
        events: [RunEvent],
        currentActionOverride: String? = nil
    ) {
        let current = steps.indices.contains(stepIndex) ? steps[stepIndex].action : nil
        let next = steps.indices.contains(stepIndex + 1) ? steps[stepIndex + 1].action : nil
        let counts = RunLiveStatus.counts(from: events)
        let remaining: Double?
        if let duration = configuredDuration {
            remaining = max(0, duration - elapsed)
        } else {
            remaining = nil
        }
        live = RunLiveStatus(
            workflowName: live.workflowName,
            phase: live.phase == .paused ? .paused : .running,
            currentStepLabel: currentActionOverride ?? Self.label(for: current),
            nextStepLabel: Self.label(for: next),
            elapsedSeconds: elapsed,
            durationSeconds: configuredDuration,
            remainingSeconds: remaining,
            eventCount: events.count,
            scrollActionCount: counts.scroll,
            keyboardActionCount: counts.keyboard
        )
    }

    public func markIdle(eventCount: Int, elapsedSeconds: Double? = nil, phase: RunUIPhase = .idle) {
        isRunning = false
        let counts = RunLiveStatus.counts(from: [])
        live = RunLiveStatus(
            workflowName: live.workflowName,
            phase: phase,
            currentStepLabel: "—",
            nextStepLabel: "—",
            elapsedSeconds: elapsedSeconds ?? live.elapsedSeconds,
            durationSeconds: configuredDuration,
            remainingSeconds: nil,
            eventCount: eventCount,
            scrollActionCount: live.scrollActionCount,
            keyboardActionCount: live.keyboardActionCount
        )
        _ = counts
        configuredDuration = nil
        recomputeCanStart()
    }

    public static func label(for action: ActionKind?) -> String {
        guard let action else { return "—" }
        return ActionPaletteItem.humanTitle(for: action)
    }

    private func recomputeCanStart() {
        canStart = accessibilityGranted && !isRunning && selectedName != nil
    }
}
