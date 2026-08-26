import Foundation
import Observability
import XCTest

final class SessionHistoryTests: XCTestCase {
    func testSummarizerCollectsAppsTargetsAndActions() {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let events = [
            RunEvent(
                timestamp: started,
                actionKind: "activateApp",
                targetBundleID: "com.todesktop.230313mzl4w4u92",
                result: .completed,
                identity: "Cursor"
            ),
            RunEvent(
                timestamp: started.addingTimeInterval(1),
                actionKind: "targetCompleted",
                targetBundleID: "com.todesktop.230313mzl4w4u92",
                result: .completed,
                identity: "User.php"
            ),
            RunEvent(
                timestamp: started.addingTimeInterval(2),
                actionKind: "scroll",
                targetBundleID: "com.google.Chrome",
                result: .completed
            ),
            RunEvent(
                timestamp: started.addingTimeInterval(3),
                actionKind: "targetCompleted",
                targetBundleID: "com.google.Chrome",
                result: .skipped,
                identity: "Ads Tab"
            ),
            RunEvent(
                timestamp: started.addingTimeInterval(4),
                actionKind: "activateApp",
                targetBundleID: "com.google.Chrome",
                result: .failed
            ),
        ]

        let record = SessionHistorySummarizer.record(
            workflowName: "Universal Workspace Navigation",
            startedAt: started,
            endedAt: started.addingTimeInterval(2_520),
            endStatus: .stopped,
            events: events
        )

        XCTAssertEqual(record.workflowName, "Universal Workspace Navigation")
        XCTAssertEqual(Int(record.durationSeconds.rounded()), 2_520)
        XCTAssertEqual(record.formattedDuration, "42 minutes")
        XCTAssertTrue(record.applicationsVisited.contains("com.google.Chrome"))
        XCTAssertTrue(record.targetsVisited.contains("User.php"))
        XCTAssertTrue(record.targetsSkipped.contains("Ads Tab"))
        XCTAssertEqual(record.failureCount, 1)
        XCTAssertEqual(record.actionsPerformed, 5)
        XCTAssertEqual(record.actionCounts["scroll"], 1)
    }

    func testGroupedByDayTodayAndYesterday() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let today = SessionHistoryRecord(
            workflowName: "A",
            startedAt: now,
            endedAt: now,
            durationSeconds: 60,
            endStatus: .completed,
            targetsVisited: ["One.swift", "Two.swift"]
        )
        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: now)!
        let yesterday = SessionHistoryRecord(
            workflowName: "B",
            startedAt: yesterdayDate,
            endedAt: yesterdayDate,
            durationSeconds: 120,
            endStatus: .stopped
        )
        let sections = [today, yesterday].groupedByDay(now: now, calendar: calendar)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].group, .today)
        XCTAssertEqual(sections[0].sessions.first?.workflowName, "A")
        XCTAssertEqual(sections[1].group, .yesterday)
    }

    func testStoreRoundTripAndClear() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("waypoint-session-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SessionHistoryStore(baseDirectory: dir, maxSessions: 10)
        let record = SessionHistoryRecord(
            workflowName: "Universal Workspace Navigation",
            startedAt: Date(),
            endedAt: Date(),
            durationSeconds: 90,
            endStatus: .completed,
            applicationsVisited: ["com.google.Chrome"],
            targetsVisited: ["Laravel Docs"],
            actionsPerformed: 12
        )
        try store.append(record)
        let loaded = try store.load()
        XCTAssertEqual(loaded.sessions.count, 1)
        XCTAssertEqual(loaded.sessions[0].workflowName, record.workflowName)
        XCTAssertEqual(loaded.sessions[0].targetsVisited, ["Laravel Docs"])

        try store.clear()
        XCTAssertTrue(try store.load().sessions.isEmpty)
    }
}
