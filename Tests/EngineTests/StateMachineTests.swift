import Actions
import CoreEngine
import Domain
import XCTest

/// Parks inside the first `execute` so the test can call `pause()` before the next step.
private actor BarrierExecutor: ActionExecutor {
    private(set) var log: [(action: ActionKind, bundleID: String)] = []
    private var firstGate: CheckedContinuation<Void, Never>?
    private var firstReleased = false

    func execute(action: ActionKind, target: TargetApp) async throws {
        log.append((action, target.bundleID))
        if log.count == 1, !firstReleased {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                firstGate = cont
            }
        }
    }

    func releaseFirst() {
        firstReleased = true
        firstGate?.resume()
        firstGate = nil
    }

    func waitUntilFirstParked(timeoutMs: Int = 2_000) async -> Bool {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1_000)
        while Date() < deadline {
            if firstGate != nil || firstReleased {
                return firstGate != nil || firstReleased
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return firstGate != nil
    }
}

/// Extra pure-logic coverage for engine pause/resume and idle invariants (merge CI).
final class StateMachineTests: XCTestCase {
    func testPauseBlocksUntilResumeThenCompletes() async {
        let clock = FakeClock()
        let executor = BarrierExecutor()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.01) }
        let engine = WorkflowEngine(
            executor: executor,
            sovereignty: ManualSovereigntySignal(),
            timing: timing
        )

        let workflow = Workflow(
            name: "pause",
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
            loop: LoopSettings(enabled: false, maxIterations: 1)
        )

        let run = Task { await engine.run(workflow) }

        let parked = await executor.waitUntilFirstParked()
        XCTAssertTrue(parked)

        await engine.pause()
        await executor.releaseFirst()

        // Engine finishes step 1 settle, then blocks at step 2 while paused.
        var sawPaused = false
        for _ in 0..<100 {
            let state = await engine.state
            if state == .paused {
                sawPaused = true
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(sawPaused)

        await engine.resume()
        await run.value

        let state = await engine.state
        XCTAssertEqual(state, .idle)
        let log = await executor.log
        XCTAssertEqual(log.count, 2)
    }

    func testSequentialRunsFromIdleEachExecute() async {
        let clock = FakeClock()
        let executor = SimulationExecutor()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.01) }
        let engine = WorkflowEngine(
            executor: executor,
            sovereignty: ManualSovereigntySignal(),
            timing: timing
        )
        let workflow = Workflow(
            name: "once",
            targets: [TargetApp(bundleID: "com.example.app", classification: .generic)],
            steps: [
                Step(
                    action: .scroll(direction: .down, amount: 1),
                    timeoutSeconds: 1,
                    retryPolicy: RetryPolicy(maxRetries: 0),
                    onError: .abort
                ),
            ],
            loop: LoopSettings(enabled: false, maxIterations: 1)
        )

        await engine.run(workflow)
        await engine.run(workflow)
        let log = await executor.log
        XCTAssertEqual(log.count, 2)
        let state = await engine.state
        XCTAssertEqual(state, .idle)
    }
}
