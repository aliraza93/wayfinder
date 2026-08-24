import Actions
import CoreEngine
import Domain
import Observability
import Safety
import XCTest

final class SafetyRoutingTests: XCTestCase {
    func testEveryActionPassesThroughSafetyGate() async {
        let lock = NSLock()
        var validated: [ActionKind] = []
        let safety = SafetyPolicy { action in
            lock.lock()
            validated.append(action)
            lock.unlock()
            return action.capabilityTags
        }

        let clock = FakeClock()
        let executor = SimulationExecutor()
        let sovereignty = ManualSovereigntySignal()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.01) }
        let engine = WorkflowEngine(
            safety: safety,
            executor: executor,
            sovereignty: sovereignty,
            timing: timing
        )

        let actions: [ActionKind] = [
            .scroll(direction: .down, amount: 1),
            .pageNavigate(.home),
            .wait(seconds: 0.1),
        ]
        let workflow = Workflow(
            name: "gated",
            targets: [TargetApp(bundleID: "com.example.app", classification: .editor)],
            steps: actions.map {
                Step(
                    action: $0,
                    timeoutSeconds: 1,
                    retryPolicy: RetryPolicy(maxRetries: 0),
                    onError: .abort
                )
            },
            loop: LoopSettings(enabled: false, maxIterations: 1)
        )

        await engine.run(workflow)

        lock.lock()
        let seen = validated
        lock.unlock()
        XCTAssertEqual(seen.count, actions.count)
        XCTAssertEqual(seen, actions)

        let events = await engine.runEvents()
        // steps + focusRestore
        XCTAssertEqual(events.count, actions.count + 1)
        XCTAssertTrue(events.dropLast().allSatisfy { $0.result == .completed })
        XCTAssertEqual(events.dropLast().map(\.actionKind), ["scroll", "pageNavigate", "wait"])
        XCTAssertEqual(events.last?.actionKind, "focusRestore")
        XCTAssertTrue(events.allSatisfy { $0.targetBundleID == "com.example.app" })
    }

    func testDeniedMutatingActionIsNotExecuted() async {
        let safety = SafetyPolicy { _ in
            CapabilityTags(
                mutatesText: true,
                requiresFocusGuard: false,
                verifiable: false,
                primitive: .none
            )
        }
        let clock = FakeClock()
        let executor = SimulationExecutor()
        let sovereignty = ManualSovereigntySignal()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.01) }
        let engine = WorkflowEngine(
            safety: safety,
            executor: executor,
            sovereignty: sovereignty,
            timing: timing
        )

        let workflow = Workflow(
            name: "denied",
            targets: [TargetApp(bundleID: "com.microsoft.VSCode", classification: .editor)],
            steps: [
                Step(
                    action: .scroll(direction: .down, amount: 1),
                    timeoutSeconds: 1,
                    retryPolicy: RetryPolicy(maxRetries: 0),
                    onError: .skip
                ),
            ],
            loop: LoopSettings(enabled: false, maxIterations: 1)
        )

        await engine.run(workflow)
        let log = await executor.log
        XCTAssertEqual(log.count, 0)
        let events = await engine.runEvents()
        XCTAssertEqual(events.first?.result, .denied)
        XCTAssertEqual(events.last?.actionKind, "focusRestore")
    }
}
