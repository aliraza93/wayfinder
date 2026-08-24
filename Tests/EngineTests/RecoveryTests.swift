import Actions
import CoreEngine
import Domain
import Observability
import Safety
import XCTest

final class RecoveryTests: XCTestCase {
    func testRetryCapAbsoluteMax() {
        XCTAssertEqual(Recovery.cappedRetries(requested: 100), Recovery.absoluteMaxRetries)
        XCTAssertEqual(Recovery.cappedRetries(requested: 0), 0)
        XCTAssertEqual(Recovery.cappedRetries(requested: 2), 2)
    }

    func testForbiddenAndPermissionMustAbortNeverRetry() {
        XCTAssertTrue(Recovery.FailureKind.forbidden("x").mustAbort)
        XCTAssertTrue(Recovery.FailureKind.permission("x").mustAbort)
        XCTAssertFalse(
            Recovery.shouldRetry(
                kind: .forbidden("no"),
                onError: .retry,
                retriesRemaining: 3
            )
        )
        XCTAssertFalse(
            Recovery.shouldRetry(
                kind: .permission("ax"),
                onError: .skip,
                retriesRemaining: 3
            )
        )
        XCTAssertEqual(
            Recovery.outcome(kind: .forbidden("x"), onError: .skip, retriesRemaining: 2),
            .aborted
        )
    }

    func testClassifyMapsTypedErrors() {
        XCTAssertEqual(
            Recovery.classify(PermissionError("ax gone")),
            .permission("ax gone")
        )
        XCTAssertEqual(
            Recovery.classify(PreconditionError("secure")),
            .precondition("secure")
        )
        XCTAssertEqual(
            Recovery.classify(TimeoutError("slow")),
            .timeout("slow")
        )
        XCTAssertEqual(
            Recovery.classify(ActionError("boom")),
            .action("boom")
        )
        XCTAssertEqual(
            Recovery.classify(ForbiddenActionError(reason: "deny")),
            .forbidden("deny")
        )
    }

    func testFocusChangeProbeStopsWithoutExecutingFurtherSteps() async {
        let probe = ScriptedPreconditionProbe(failures: [
            nil,
            PreconditionError("focus changed before event (TOCTOU)"),
        ])
        let clock = FakeClock()
        let executor = SimulationExecutor()
        let sovereignty = ManualSovereigntySignal()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.01) }
        let engine = WorkflowEngine(
            executor: executor,
            sovereignty: sovereignty,
            timing: timing,
            preconditionProbe: probe
        )

        let workflow = Workflow(
            name: "toctou",
            targets: [TargetApp(bundleID: "com.example.app", classification: .generic)],
            steps: [
                Step(
                    action: .scroll(direction: .down, amount: 1),
                    timeoutSeconds: 1,
                    retryPolicy: RetryPolicy(maxRetries: 5),
                    onError: .retry
                ),
                Step(
                    action: .scroll(direction: .up, amount: 1),
                    timeoutSeconds: 1,
                    retryPolicy: RetryPolicy(maxRetries: 5),
                    onError: .retry
                ),
            ],
            loop: LoopSettings(enabled: false, maxIterations: 1)
        )

        await engine.run(workflow)
        let log = await executor.log
        XCTAssertEqual(log.count, 1, "second step must not execute after focus change")
        let message = await engine.lastRecoveryMessage
        XCTAssertTrue(message?.contains("focus changed") == true)
        let state = await engine.state
        XCTAssertEqual(state, .idle)
        let restore = await engine.focusRestoreResult
        XCTAssertEqual(restore, .restored)
    }

    func testPermissionLossStopsAndNeverSkips() async {
        let probe = ScriptedPreconditionProbe(failures: [
            PermissionError("accessibility focus lost mid-run"),
        ])
        let clock = FakeClock()
        let executor = SimulationExecutor()
        let sovereignty = ManualSovereigntySignal()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.01) }
        let engine = WorkflowEngine(
            executor: executor,
            sovereignty: sovereignty,
            timing: timing,
            preconditionProbe: probe
        )

        let workflow = Workflow(
            name: "perm",
            targets: [TargetApp(bundleID: "com.example.app", classification: .generic)],
            steps: [
                Step(
                    action: .scroll(direction: .down, amount: 1),
                    timeoutSeconds: 1,
                    retryPolicy: RetryPolicy(maxRetries: 2),
                    onError: .skip
                ),
            ],
            loop: LoopSettings(enabled: false, maxIterations: 1)
        )

        await engine.run(workflow)
        let log = await executor.log
        XCTAssertEqual(log.count, 0)
        let events = await engine.runEvents()
        XCTAssertTrue(events.contains { $0.actionKind == "scroll" && $0.result == .failed })
        XCTAssertFalse(events.contains { $0.result == .skipped })
        let message = await engine.lastRecoveryMessage
        XCTAssertTrue(message?.contains("accessibility") == true)
    }

    func testSecureInputSurfacesPreconditionAndStops() async {
        let probe = ScriptedPreconditionProbe(failures: [
            PreconditionError("Secure Input is enabled; synthetic navigation cannot proceed"),
        ])
        let clock = FakeClock()
        let executor = SimulationExecutor()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.01) }
        let engine = WorkflowEngine(
            executor: executor,
            sovereignty: ManualSovereigntySignal(),
            timing: timing,
            preconditionProbe: probe
        )

        let workflow = Workflow(
            name: "secure",
            targets: [TargetApp(bundleID: "com.example.app", classification: .generic)],
            steps: [
                Step(
                    action: .scroll(direction: .down, amount: 1),
                    timeoutSeconds: 1,
                    retryPolicy: RetryPolicy(maxRetries: 3),
                    onError: .retry
                ),
            ],
            loop: LoopSettings(enabled: false, maxIterations: 1)
        )

        await engine.run(workflow)
        let log = await executor.log
        XCTAssertEqual(log.count, 0)
        let message = await engine.lastRecoveryMessage
        XCTAssertTrue(message?.lowercased().contains("secure input") == true)
    }

    func testFocusRestoreFailureLoggedHonestly() async {
        let restorer = RecordingFocusRestorer(result: .couldNotRestore)
        let clock = FakeClock()
        let executor = SimulationExecutor()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.01) }
        let engine = WorkflowEngine(
            executor: executor,
            sovereignty: ManualSovereigntySignal(),
            timing: timing,
            focusRestorer: restorer
        )

        let workflow = Workflow(
            name: "restore",
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
        XCTAssertEqual(restorer.requestedBundleIDs, ["com.example.app"])
        let restore = await engine.focusRestoreResult
        XCTAssertEqual(restore, .couldNotRestore)
        let message = await engine.lastRecoveryMessage
        XCTAssertEqual(message, "couldn't restore focus")
        let events = await engine.runEvents()
        XCTAssertEqual(events.last?.actionKind, "focusRestore")
        XCTAssertEqual(events.last?.result, .failed)
        let state = await engine.state
        XCTAssertEqual(state, .idle)
    }

    func testActionFailureRespectsRetryCapThenAborts() async {
        let clock = FakeClock()
        let executor = CountingFailExecutor()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.01) }
        let engine = WorkflowEngine(
            executor: executor,
            sovereignty: ManualSovereigntySignal(),
            timing: timing
        )

        let workflow = Workflow(
            name: "retry-cap",
            targets: [TargetApp(bundleID: "com.example.app", classification: .generic)],
            steps: [
                Step(
                    action: .scroll(direction: .down, amount: 1),
                    timeoutSeconds: 1,
                    // Request more than absolute max — must clamp.
                    retryPolicy: RetryPolicy(maxRetries: 50),
                    onError: .retry
                ),
            ],
            loop: LoopSettings(enabled: false, maxIterations: 1)
        )

        await engine.run(workflow)
        let attempts = await executor.attempts
        // initial attempt + absoluteMaxRetries retries
        XCTAssertEqual(attempts, Recovery.absoluteMaxRetries + 1)
        let state = await engine.state
        XCTAssertEqual(state, .idle)
    }

    func testTimeoutErrorAbortsWaitStep() async {
        // Clock never advances enough relative to wait seconds within tiny timeout.
        let clock = FakeClock()
        let executor = SimulationExecutor()
        let timing = TimingPolicy(clock: clock) {
            // Advance very little so wait predicate never becomes true before budget.
            clock.advance(by: 0.001)
        }
        let engine = WorkflowEngine(
            executor: executor,
            sovereignty: ManualSovereigntySignal(),
            timing: timing
        )

        let workflow = Workflow(
            name: "timeout",
            targets: [TargetApp(bundleID: "com.example.app", classification: .generic)],
            steps: [
                Step(
                    action: .wait(seconds: 5),
                    timeoutSeconds: 0.01,
                    retryPolicy: RetryPolicy(maxRetries: 0),
                    onError: .abort
                ),
            ],
            loop: LoopSettings(enabled: false, maxIterations: 1)
        )

        await engine.run(workflow)
        let message = await engine.lastRecoveryMessage
        XCTAssertTrue(message?.lowercased().contains("timeout") == true || message?.contains("wait") == true)
        let events = await engine.runEvents()
        XCTAssertTrue(events.contains { $0.actionKind == "wait" && $0.result == .failed })
        let state = await engine.state
        XCTAssertEqual(state, .idle)
    }
}

private actor CountingFailExecutor: ActionExecutor {
    private(set) var attempts = 0

    func execute(action: ActionKind, target: TargetApp) async throws {
        _ = action
        _ = target
        attempts += 1
        throw ActionError("forced failure")
    }
}
