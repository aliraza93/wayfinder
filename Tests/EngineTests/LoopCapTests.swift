import Actions
import CoreEngine
import Domain
import XCTest

final class LoopCapTests: XCTestCase {
    func testMaxIterationCap() async {
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
            name: "loop",
            targets: [TargetApp(bundleID: "com.example.app", classification: .generic)],
            steps: [
                Step(
                    action: .scroll(direction: .down, amount: 1),
                    timeoutSeconds: 1,
                    retryPolicy: RetryPolicy(maxRetries: 0),
                    onError: .abort
                ),
            ],
            loop: LoopSettings(enabled: true, maxIterations: 3, maxDurationSeconds: nil)
        )

        await engine.run(workflow)
        let iterations = await engine.iterationsCompleted
        XCTAssertEqual(iterations, 3)
        let log = await executor.log
        XCTAssertEqual(log.count, 3)
    }

    func testWallClockCapStopsEarly() async {
        let clock = FakeClock()
        let executor = SimulationExecutor()
        let sovereignty = ManualSovereigntySignal()
        let timing = TimingPolicy(clock: clock) {
            clock.advance(by: 5)
        }
        let engine = WorkflowEngine(
            executor: executor,
            sovereignty: sovereignty,
            timing: timing
        )

        let workflow = Workflow(
            name: "timed",
            targets: [TargetApp(bundleID: "com.example.app", classification: .generic)],
            steps: [
                Step(
                    action: .scroll(direction: .down, amount: 1),
                    timeoutSeconds: 1,
                    retryPolicy: RetryPolicy(maxRetries: 0),
                    onError: .abort
                ),
            ],
            loop: LoopSettings(enabled: true, maxIterations: 100, maxDurationSeconds: 10)
        )

        await engine.run(workflow)
        let log = await executor.log
        // Each iteration settles with onPoll advances; duration cap should keep count modest.
        XCTAssertLessThan(log.count, 100)
        XCTAssertGreaterThanOrEqual(log.count, 1)
    }
}
