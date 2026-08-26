import Foundation

/// How a recorded session ended (local history only).
public enum SessionEndStatus: String, Equatable, Sendable, Codable {
    case completed
    case stopped
    case failed

    public var title: String {
        switch self {
        case .completed: return "Completed"
        case .stopped: return "Stopped"
        case .failed: return "Failed"
        }
    }
}

/// One locally stored workflow session — identity metadata only, never page/document body.
public struct SessionHistoryRecord: Equatable, Sendable, Identifiable, Codable {
    public var id: String
    public var workflowName: String
    public var startedAt: Date
    public var endedAt: Date
    public var durationSeconds: Double
    public var endStatus: SessionEndStatus
    /// Bundle IDs visited during the run (no window titles beyond configured identity).
    public var applicationsVisited: [String]
    /// User-configured identities (file names / tab labels) that completed.
    public var targetsVisited: [String]
    /// Identities skipped during the run.
    public var targetsSkipped: [String]
    public var failureCount: Int
    /// Privacy-safe action kind → count (e.g. scroll, activateApp).
    public var actionCounts: [String: Int]
    public var actionsPerformed: Int

    public init(
        id: String = UUID().uuidString,
        workflowName: String,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Double,
        endStatus: SessionEndStatus,
        applicationsVisited: [String] = [],
        targetsVisited: [String] = [],
        targetsSkipped: [String] = [],
        failureCount: Int = 0,
        actionCounts: [String: Int] = [:],
        actionsPerformed: Int = 0
    ) {
        self.id = id
        self.workflowName = workflowName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.endStatus = endStatus
        self.applicationsVisited = applicationsVisited
        self.targetsVisited = targetsVisited
        self.targetsSkipped = targetsSkipped
        self.failureCount = failureCount
        self.actionCounts = actionCounts
        self.actionsPerformed = actionsPerformed
    }

    public var targetsTouched: Int {
        Set(targetsVisited + targetsSkipped).count
    }

    public var formattedDuration: String {
        let total = max(0, Int(durationSeconds.rounded()))
        if total < 60 { return "\(total) seconds" }
        let minutes = Int((Double(total) / 60.0).rounded())
        if minutes == 1 { return "1 minute" }
        return "\(minutes) minutes"
    }
}

/// Document persisted at `~/Library/Application Support/Waypoint/session-history.json`.
public struct SessionHistoryDocument: Equatable, Sendable, Codable {
    public var schemaVersion: Int
    public var sessions: [SessionHistoryRecord]

    public init(schemaVersion: Int = 1, sessions: [SessionHistoryRecord] = []) {
        self.schemaVersion = schemaVersion
        self.sessions = sessions
    }
}

/// Builds a privacy-respecting session record from content-free run events.
public enum SessionHistorySummarizer: Sendable {
    public static func record(
        workflowName: String,
        startedAt: Date,
        endedAt: Date = Date(),
        endStatus: SessionEndStatus,
        events: [RunEvent]
    ) -> SessionHistoryRecord {
        var apps = Set<String>()
        var visited = Set<String>()
        var skipped = Set<String>()
        var failures = 0
        var actionCounts: [String: Int] = [:]

        for event in events {
            let bundle = event.targetBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !bundle.isEmpty {
                apps.insert(bundle)
            }
            let kind = event.actionKind.trimmingCharacters(in: .whitespacesAndNewlines)
            if !kind.isEmpty {
                actionCounts[kind, default: 0] += 1
            }
            if event.result == .failed {
                failures += 1
            }

            let identity = event.identity?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !identity.isEmpty, identity.count <= 160 {
                switch event.result {
                case .skipped:
                    skipped.insert(identity)
                case .completed:
                    if isTargetCompletion(event.actionKind) || looksLikeSurfaceIdentity(identity) {
                        visited.insert(identity)
                    }
                case .failed, .denied:
                    break
                }
            }
            if event.result == .skipped, !identity.isEmpty, identity.count <= 160 {
                skipped.insert(identity)
            }
        }

        // Prefer completed target identities; drop ones that were only skipped.
        for skip in skipped {
            if visited.contains(skip) {
                skipped.remove(skip)
            }
        }

        let duration = max(0, endedAt.timeIntervalSince(startedAt))
        return SessionHistoryRecord(
            workflowName: workflowName.isEmpty ? "Untitled" : workflowName,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: duration,
            endStatus: endStatus,
            applicationsVisited: apps.sorted(),
            targetsVisited: visited.sorted(),
            targetsSkipped: skipped.sorted(),
            failureCount: failures,
            actionCounts: actionCounts,
            actionsPerformed: events.count
        )
    }

    private static func isTargetCompletion(_ actionKind: String) -> Bool {
        switch actionKind {
        case "targetCompleted", "fileOpened", "surfaceSelected", "webNavActivated",
             "applicationFocused", "surfaceSwitched":
            return true
        default:
            return false
        }
    }

    private static func looksLikeSurfaceIdentity(_ identity: String) -> Bool {
        // Configured file/tab labels — short identity strings only.
        if identity.contains("/") { return true }
        if identity.contains(".") { return true }
        return identity.count <= 80
    }
}

/// Calendar grouping for the Sessions list.
public enum SessionHistoryDayGroup: Equatable, Sendable, Identifiable {
    case today
    case yesterday
    case day(Date)

    public var id: String {
        switch self {
        case .today: return "today"
        case .yesterday: return "yesterday"
        case .day(let date):
            return ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: date))
        }
    }

    public var title: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .day(let date):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }

    public static func group(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SessionHistoryDayGroup {
        if calendar.isDateInToday(date) { return .today }
        if calendar.isDateInYesterday(date) { return .yesterday }
        return .day(calendar.startOfDay(for: date))
    }
}

public struct SessionHistorySection: Equatable, Sendable, Identifiable {
    public var group: SessionHistoryDayGroup
    public var sessions: [SessionHistoryRecord]

    public var id: String { group.id }

    public init(group: SessionHistoryDayGroup, sessions: [SessionHistoryRecord]) {
        self.group = group
        self.sessions = sessions
    }
}

extension Array where Element == SessionHistoryRecord {
    public func groupedByDay(now: Date = Date(), calendar: Calendar = .current) -> [SessionHistorySection] {
        let sorted = self.sorted { $0.startedAt > $1.startedAt }
        var order: [SessionHistoryDayGroup] = []
        var buckets: [String: [SessionHistoryRecord]] = [:]
        for session in sorted {
            let group = SessionHistoryDayGroup.group(for: session.startedAt, now: now, calendar: calendar)
            if buckets[group.id] == nil {
                order.append(group)
                buckets[group.id] = []
            }
            buckets[group.id, default: []].append(session)
        }
        return order.map { SessionHistorySection(group: $0, sessions: buckets[$0.id] ?? []) }
    }
}
