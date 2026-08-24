import Actions
import CoreEngine
import Domain
import InputSynthesis
import Observability
import Safety
import WaypointAccessibility
import XCTest

final class SkeletonWiringTests: XCTestCase {
    func testHardcodedSkeletonWorkflowViaRealExecutorRecordingSeam() async throws {
        let probe = StaticFrontmostProbe(bundleID: "com.google.Chrome")
        let clock = FakeClock()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.2) }
        let focus = FocusGuard(probe: probe, timing: timing, debounceSeconds: 0.1)
        let poster = RecordingEventPoster()
        let sovereignty = UserSovereigntyMonitor(secureInput: NullSecureInputProbe())
        let synth = EventSynth(
            focusGuard: focus,
            poster: poster,
            sovereignty: sovereignty
        )
        let executor = RealExecutor(synth: synth)
        let recorder = RunRecorder()
        let engine = WorkflowEngine(
            executor: executor,
            sovereignty: sovereignty,
            timing: timing,
            recorder: recorder
        )

        let workflow = SkeletonWorkflow.make(frontmostBundleID: "com.google.Chrome", iterations: 2)
        await engine.run(workflow)

        let state = await engine.state
        XCTAssertEqual(state, .idle)

        // Each iteration: scroll down + scroll up (waits are not posted).
        XCTAssertEqual(poster.events.count, 4)
        XCTAssertTrue(poster.events.allSatisfy(\.tagged))
        XCTAssertEqual(
            poster.events.map { event -> String in
                if case .scroll(let d) = event.kind { return d < 0 ? "down" : "up" }
                return "?"
            },
            ["down", "up", "down", "up"]
        )

        let events = recorder.snapshot()
        // scroll + wait + scroll + wait, twice + focusRestore
        XCTAssertEqual(events.count, 9)
        XCTAssertTrue(events.allSatisfy { $0.targetBundleID == "com.google.Chrome" })
        XCTAssertEqual(Set(events.dropLast().map(\.actionKind)), Set(["scroll", "wait"]))
        XCTAssertEqual(events.last?.actionKind, "focusRestore")
        XCTAssertTrue(events.allSatisfy { $0.result == .completed })
    }

    func testSimulationSeamStillWorksForEngine() async {
        let clock = FakeClock()
        let executor = SimulationExecutor()
        let sovereignty = ManualSovereigntySignal()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.05) }
        let engine = WorkflowEngine(
            executor: executor,
            sovereignty: sovereignty,
            timing: timing
        )
        let workflow = SkeletonWorkflow.make(frontmostBundleID: "com.example.app", iterations: 1)
        await engine.run(workflow)
        let log = await executor.log
        XCTAssertEqual(log.count, 2) // wait handled by engine; two scrolls executed
    }
}

private struct StaticFrontmostProbe: AXProbe {
    var bundleID: String?
    func frontmostAppBundleID() -> String? { bundleID }
    func focusedWindowExists() -> Bool { true }
    func focusedElementBundleID() -> String? { bundleID }
}
