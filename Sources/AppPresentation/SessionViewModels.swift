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
            return "Enable Waypoint in System Settings → Privacy & Security → Accessibility, then return here."
        case .granted:
            return "You’re ready to build and run read-only navigation workflows."
        }
    }
}

/// Live run status for the menu bar (updated on main by the session controller).
public struct RunLiveStatus: Equatable, Sendable {
    public var workflowName: String
    public var isRunning: Bool
    public var currentStepLabel: String
    public var nextStepLabel: String
    public var elapsedSeconds: Double
    public var eventCount: Int

    public init(
        workflowName: String = "",
        isRunning: Bool = false,
        currentStepLabel: String = "—",
        nextStepLabel: String = "—",
        elapsedSeconds: Double = 0,
        eventCount: Int = 0
    ) {
        self.workflowName = workflowName
        self.isRunning = isRunning
        self.currentStepLabel = currentStepLabel
        self.nextStepLabel = nextStepLabel
        self.elapsedSeconds = elapsedSeconds
        self.eventCount = eventCount
    }

    public var summaryLine: String {
        if isRunning {
            return "Running \(workflowName): \(currentStepLabel) → next \(nextStepLabel) (\(Int(elapsedSeconds))s)"
        }
        if workflowName.isEmpty {
            return "Idle"
        }
        return "Last: \(workflowName) (\(eventCount) events)"
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

    public func markRunning(workflowName: String, steps: [Step]) {
        isRunning = true
        live = RunLiveStatus(
            workflowName: workflowName,
            isRunning: true,
            currentStepLabel: Self.label(for: steps.first?.action),
            nextStepLabel: Self.label(for: steps.dropFirst().first?.action),
            elapsedSeconds: 0,
            eventCount: 0
        )
        recomputeCanStart()
    }

    public func updateProgress(stepIndex: Int, steps: [Step], elapsed: Double, eventCount: Int) {
        let current = steps.indices.contains(stepIndex) ? steps[stepIndex].action : nil
        let next = steps.indices.contains(stepIndex + 1) ? steps[stepIndex + 1].action : nil
        live = RunLiveStatus(
            workflowName: live.workflowName,
            isRunning: true,
            currentStepLabel: Self.label(for: current),
            nextStepLabel: Self.label(for: next),
            elapsedSeconds: elapsed,
            eventCount: eventCount
        )
    }

    public func markIdle(eventCount: Int, elapsedSeconds: Double? = nil) {
        isRunning = false
        live = RunLiveStatus(
            workflowName: live.workflowName,
            isRunning: false,
            currentStepLabel: "—",
            nextStepLabel: "—",
            elapsedSeconds: elapsedSeconds ?? live.elapsedSeconds,
            eventCount: eventCount
        )
        recomputeCanStart()
    }

    public static func label(for action: ActionKind?) -> String {
        guard let action else { return "—" }
        switch action {
        case .scroll(let d, _): return "scroll \(d)"
        case .pageNavigate(let m): return "page \(m)"
        case .wait(let s): return String(format: "wait %.1fs", s)
        case .activateApp: return "activate"
        case .switchWindow: return "switch window"
        case .openExistingFile: return "open file"
        case .returnToPrevious: return "return"
        }
    }

    private func recomputeCanStart() {
        canStart = accessibilityGranted && !isRunning && selectedName != nil
    }
}
