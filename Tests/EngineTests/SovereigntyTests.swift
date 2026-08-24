import Actions
import CoreEngine
import Domain
import XCTest

final class SovereigntyTests: XCTestCase {
    func testStopSignalHaltsWithinOneStep() async {
        let clock = FakeClock()
        let executor = SimulationExecutor()
        let sovereignty = ManualSovereigntySignal()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.01) }

        let engine = WorkflowEngine(
            executor: executor,
            sovereignty: sovereignty,
            timing: timing
        )

        // Request stop before run — should halt immediately (no steps executed).
        await sovereignty.requestStop()

        let workflow = Workflow(
            name: "stop",
            targets: [TargetApp(bundleID: "com.example.app", classification: .generic)],
            steps: [
                Step(
                    action: .scroll(direction: .down, amount: 1),
                    timeoutSeconds: 1,
                    retryPolicy: RetryPolicy(maxRetries: 0),
                    onError: .abort
                ),
                Step(
                    action: .scroll(direction: .up, amount: 1),
                    timeoutSeconds: 1,
                    retryPolicy: RetryPolicy(maxRetries: 0),
                    onError: .abort
                ),
            ],
            loop: LoopSettings(enabled: true, maxIterations: 10)
        )

        await engine.run(workflow)
        let log = await executor.log
        XCTAssertEqual(log.count, 0)
        let state = await engine.state
        XCTAssertEqual(state, .idle)
    }

    func testUserInterventionHaltsAfterSignal() async {
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
            name: "intervene",
            targets: [TargetApp(bundleID: "com.example.app", classification: .generic)],
            steps: [
                Step(
                    action: .scroll(direction: .down, amount: 1),
                    timeoutSeconds: 1,
                    retryPolicy: RetryPolicy(maxRetries: 0),
                    onError: .abort
                ),
            ],
            loop: LoopSettings(enabled: true, maxIterations: 5)
        )

        // Fire intervention concurrently after a tiny yield so at most a few steps run.
        let runner = Task {
            await engine.run(workflow)
        }
        await Task.yield()
        await sovereignty.noteUserIntervention()
        await runner.value

        let log = await executor.log
        XCTAssertLessThan(log.count, 5)
        let state = await engine.state
        XCTAssertEqual(state, .idle)
    }
}
