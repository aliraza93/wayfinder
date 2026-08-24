import Actions
import CoreEngine
import Domain
import Observability
import Safety
import XCTest

final class RetargetTests: XCTestCase {
    func testActivateAppRetargetsSubsequentScroll() async {
        let clock = FakeClock()
        let executor = SimulationExecutor()
        let sovereignty = ManualSovereigntySignal()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.01) }
        let engine = WorkflowEngine(
            executor: executor,
            sovereignty: sovereignty,
            timing: timing
        )

        let cursor = TargetApp(bundleID: "com.todesktop.230313mzl4w4u92", classification: .editor)
        let chrome = TargetApp(bundleID: "com.google.Chrome", classification: .browser)

        let workflow = Workflow(
            name: "retarget",
            targets: [cursor, chrome],
            steps: [
                Step(action: .scroll(direction: .down, amount: 1), timeoutSeconds: 1, retryPolicy: RetryPolicy(maxRetries: 0), onError: .abort),
                Step(action: .activateApp(bundleID: chrome.bundleID), timeoutSeconds: 1, retryPolicy: RetryPolicy(maxRetries: 0), onError: .abort),
                Step(action: .scroll(direction: .down, amount: 1), timeoutSeconds: 1, retryPolicy: RetryPolicy(maxRetries: 0), onError: .abort),
                Step(action: .returnToPrevious, timeoutSeconds: 1, retryPolicy: RetryPolicy(maxRetries: 0), onError: .abort),
                Step(action: .scroll(direction: .up, amount: 1), timeoutSeconds: 1, retryPolicy: RetryPolicy(maxRetries: 0), onError: .abort),
            ],
            loop: LoopSettings(enabled: false, maxIterations: 1)
        )

        await engine.run(workflow)

        let log = await executor.log
        XCTAssertEqual(log.count, 5)
        XCTAssertEqual(log[0].bundleID, cursor.bundleID)
        XCTAssertEqual(log[1].action, .activateApp(bundleID: chrome.bundleID))
        XCTAssertEqual(log[1].bundleID, chrome.bundleID)
        XCTAssertEqual(log[2].bundleID, chrome.bundleID)
        XCTAssertEqual(log[3].action, .activateApp(bundleID: cursor.bundleID))
        XCTAssertEqual(log[3].bundleID, cursor.bundleID)
        XCTAssertEqual(log[4].bundleID, cursor.bundleID)

        let events = await engine.runEvents()
        let activateEvents = events.filter { $0.actionKind == "activateApp" }
        XCTAssertEqual(activateEvents.map(\.targetBundleID), [chrome.bundleID])
        let returns = events.filter { $0.actionKind == "returnToPrevious" }
        XCTAssertEqual(returns.map(\.targetBundleID), [cursor.bundleID])
        let endReason = await engine.endReason
        XCTAssertEqual(endReason, .completed)
    }

    func testReturnWithEmptyStackIsSkipped() async {
        let clock = FakeClock()
        let executor = SimulationExecutor()
        let sovereignty = ManualSovereigntySignal()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.01) }
        let engine = WorkflowEngine(
            executor: executor,
            sovereignty: sovereignty,
            timing: timing
        )

        let workflow = Workflow(
            name: "empty-return",
            targets: [TargetApp(bundleID: "com.example.app", classification: .editor)],
            steps: [
                Step(action: .returnToPrevious, timeoutSeconds: 1, retryPolicy: RetryPolicy(maxRetries: 0), onError: .abort),
            ],
            loop: LoopSettings(enabled: false, maxIterations: 1)
        )

        await engine.run(workflow)
        let log = await executor.log
        XCTAssertTrue(log.isEmpty)
        let events = await engine.runEvents()
        XCTAssertTrue(events.contains { $0.actionKind == "returnToPrevious" && $0.result == .skipped })
        let endReason = await engine.endReason
        XCTAssertEqual(endReason, .completed)
    }
}
