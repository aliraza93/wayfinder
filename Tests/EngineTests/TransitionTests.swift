import Actions
import CoreEngine
import Domain
import XCTest

final class TransitionTests: XCTestCase {
    func testMultiStepWorkflowCompletesAndReturnsToIdle() async throws {
        let clock = FakeClock()
        let executor = SimulationExecutor()
        let sovereignty = ManualSovereigntySignal()
        let timing = TimingPolicy(clock: clock) {
            clock.advance(by: 0.1)
        }
        let engine = WorkflowEngine(
            executor: executor,
            sovereignty: sovereignty,
            timing: timing
        )

        let workflow = Workflow(
            name: "sim",
            targets: [TargetApp(bundleID: "com.example.app", classification: .generic)],
            steps: [
                Step(
                    action: .scroll(direction: .down, amount: 1),
                    timeoutSeconds: 1,
                    retryPolicy: RetryPolicy(maxRetries: 0),
                    onError: .abort
                ),
                Step(
                    action: .pageNavigate(.pageDown),
                    timeoutSeconds: 1,
                    retryPolicy: RetryPolicy(maxRetries: 0),
                    onError: .abort
                ),
            ],
            loop: LoopSettings(enabled: false, maxIterations: 1)
        )

        await engine.run(workflow)

        let state = await engine.state
        XCTAssertEqual(state, .idle)
        let log = await executor.log
        XCTAssertEqual(log.count, 2)
        XCTAssertEqual(log[0].action, .scroll(direction: .down, amount: 1))
        XCTAssertEqual(log[1].action, .pageNavigate(.pageDown))

        let events = await engine.runEvents()
        XCTAssertEqual(events.map(\.result), [.completed, .completed, .completed])
        XCTAssertEqual(events.map(\.actionKind), ["scroll", "pageNavigate", "focusRestore"])
        XCTAssertTrue(events.allSatisfy { $0.targetBundleID == "com.example.app" })
    }

    func testErrorPathReachesStoppingThenIdle() async {
        let clock = FakeClock()
        let executor = SimulationExecutor()
        await executor.setShouldFail(true)

        let sovereignty = ManualSovereigntySignal()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.1) }
        let engine = WorkflowEngine(
            executor: executor,
            sovereignty: sovereignty,
            timing: timing
        )

        let workflow = Workflow(
            name: "fail",
            targets: [TargetApp(bundleID: "com.example.app", classification: .generic)],
            steps: [
                Step(
                    action: .scroll(direction: .up, amount: 1),
                    timeoutSeconds: 1,
                    retryPolicy: RetryPolicy(maxRetries: 0),
                    onError: .abort
                ),
            ],
            loop: LoopSettings(enabled: false, maxIterations: 1)
        )

        await engine.run(workflow)
        let state = await engine.state
        XCTAssertEqual(state, .idle)
        let events = await engine.runEvents()
        XCTAssertEqual(events.first?.result, .failed)
        XCTAssertEqual(events.last?.actionKind, "focusRestore")
    }
}
