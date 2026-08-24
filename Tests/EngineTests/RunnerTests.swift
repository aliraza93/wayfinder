import Actions
import Adapters
import Config
import CoreEngine
import Domain
import Observability
import Safety
import XCTest

final class RunnerTests: XCTestCase {
    func testLoadsMultiTargetWorkflowAndRunsViaSimulationSeam() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaypointRunner-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let store = ConfigStore(baseDirectory: temp)
        try store.save(WorkflowRunner.sampleMultiTargetDocument())

        let clock = FakeClock()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.05) }
        let executor = SimulationExecutor()
        let sovereignty = ManualSovereigntySignal()
        let recorder = RunRecorder()
        let runner = WorkflowRunner(store: store)

        let summary = try await runner.run(
            workflowName: "multi-target-scroll",
            executor: executor,
            sovereignty: sovereignty,
            timing: timing,
            recorder: recorder,
            resolver: PermissiveTargetResolver()
        )

        XCTAssertEqual(summary.workflowName, "multi-target-scroll")
        XCTAssertEqual(summary.adapters["com.google.Chrome"], .browser)
        XCTAssertEqual(summary.adapters["com.microsoft.VSCode"], .editor)
        XCTAssertEqual(summary.adapters["com.apple.finder"], .generic)

        let log = await executor.log
        XCTAssertFalse(log.isEmpty)
        // Primary target is Chrome (first in list).
        XCTAssertTrue(log.allSatisfy { $0.bundleID == "com.google.Chrome" })

        let events = summary.events
        XCTAssertFalse(events.isEmpty)
        XCTAssertTrue(events.allSatisfy { event in
            event.targetBundleID == "com.google.Chrome"
                && ["scroll", "wait", "pageNavigate", "focusRestore"].contains(event.actionKind)
        })
        // Content-free: only known fields populated (no free-form document text).
        XCTAssertTrue(events.allSatisfy { !$0.actionKind.isEmpty && !$0.targetBundleID.isEmpty })
    }

    func testValidationRejectsIllegalWorkflowBeforeAnyAction() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaypointRunnerBad-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let mutatingTags = CapabilityTags(
            mutatesText: true,
            requiresFocusGuard: false,
            verifiable: true,
            primitive: .none
        )
        let badValidator = WorkflowValidator { _ in mutatingTags }
        let store = ConfigStore(baseDirectory: temp, validator: WorkflowValidator())
        // Save with normal validator first.
        let workflow = Workflow(
            name: "illegal",
            targets: [TargetApp(bundleID: "com.microsoft.VSCode", classification: .editor)],
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
        try store.save(WorkflowConfigDocument(workflows: [workflow]))

        let executor = SimulationExecutor()
        let clock = FakeClock()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.01) }
        let runner = WorkflowRunner(store: store, configValidator: badValidator)

        do {
            _ = try await runner.run(
                workflowName: "illegal",
                executor: executor,
                sovereignty: ManualSovereigntySignal(),
                timing: timing,
                resolver: PermissiveTargetResolver()
            )
            XCTFail("expected validation failure")
        } catch let error as WorkflowRunnerError {
            guard case .validationFailed = error else {
                return XCTFail("expected validationFailed, got \(error)")
            }
        }

        let log = await executor.log
        XCTAssertTrue(log.isEmpty, "executor must not run when validation fails")
    }

    func testSafetyDenialPreventsStart() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaypointRunnerSafety-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let store = ConfigStore(baseDirectory: temp)
        try store.save(WorkflowRunner.sampleMultiTargetDocument())

        let denyingSafety = SafetyPolicy { _ in
            CapabilityTags(
                mutatesText: true,
                requiresFocusGuard: true,
                verifiable: false,
                primitive: .scrollWheel
            )
        }
        let executor = SimulationExecutor()
        let clock = FakeClock()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.01) }
        let runner = WorkflowRunner(store: store, safety: denyingSafety)

        do {
            _ = try await runner.run(
                workflowName: "multi-target-scroll",
                executor: executor,
                sovereignty: ManualSovereigntySignal(),
                timing: timing
            )
            XCTFail("expected safety denial")
        } catch let error as WorkflowRunnerError {
            guard case .safetyDenied = error else {
                return XCTFail("expected safetyDenied, got \(error)")
            }
        }
        let log = await executor.log
        XCTAssertTrue(log.isEmpty)
    }

    func testUnavailableTargetRefusedBeforeRun() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaypointRunnerMissing-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let store = ConfigStore(baseDirectory: temp)
        try store.save(WorkflowRunner.sampleMultiTargetDocument())

        struct NoneAvailable: WorkflowTargetResolver {
            func isAvailable(bundleID: String) -> Bool { false }
        }

        let executor = SimulationExecutor()
        let clock = FakeClock()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.01) }
        let runner = WorkflowRunner(store: store)

        do {
            _ = try await runner.run(
                workflowName: "multi-target-scroll",
                executor: executor,
                sovereignty: ManualSovereigntySignal(),
                timing: timing,
                resolver: NoneAvailable()
            )
            XCTFail("expected targetUnavailable")
        } catch let error as WorkflowRunnerError {
            guard case .targetUnavailable = error else {
                return XCTFail("expected targetUnavailable, got \(error)")
            }
        }
        let log = await executor.log
        XCTAssertTrue(log.isEmpty)
    }

    func testLoopCapHonoredThroughRunner() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaypointRunnerLoop-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let workflow = Workflow(
            name: "capped",
            targets: [TargetApp(bundleID: "com.google.Chrome", classification: .browser)],
            steps: [
                Step(
                    action: .scroll(direction: .down, amount: 1),
                    timeoutSeconds: 1,
                    retryPolicy: RetryPolicy(maxRetries: 0),
                    onError: .abort
                ),
            ],
            loop: LoopSettings(enabled: true, maxIterations: 3)
        )
        let store = ConfigStore(baseDirectory: temp)
        try store.save(WorkflowConfigDocument(workflows: [workflow]))

        let executor = SimulationExecutor()
        let clock = FakeClock()
        let timing = TimingPolicy(clock: clock) { clock.advance(by: 0.01) }
        let runner = WorkflowRunner(store: store)
        _ = try await runner.run(
            workflowName: "capped",
            executor: executor,
            sovereignty: ManualSovereigntySignal(),
            timing: timing
        )
        let log = await executor.log
        XCTAssertEqual(log.count, 3)
    }
}
