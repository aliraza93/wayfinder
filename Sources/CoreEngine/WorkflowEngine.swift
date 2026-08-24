import Domain
import Foundation
import Observability
import Safety

/// Sequencer / state machine. Routes every action through `SafetyPolicy` before execution.
public actor WorkflowEngine {
    public private(set) var state: EngineState = .idle
    public private(set) var lastStepPhase: StepPhase = .pending
    public private(set) var iterationsCompleted: Int = 0

    private let safety: SafetyPolicy
    private let executor: ActionExecutor
    private let sovereignty: UserSovereigntySignal
    private let timing: TimingPolicy
    private let recorder: RunRecorder

    public init(
        safety: SafetyPolicy = SafetyPolicy(),
        executor: ActionExecutor,
        sovereignty: UserSovereigntySignal,
        timing: TimingPolicy,
        recorder: RunRecorder = RunRecorder()
    ) {
        self.safety = safety
        self.executor = executor
        self.sovereignty = sovereignty
        self.timing = timing
        self.recorder = recorder
    }

    public func runEvents() -> [RunEvent] {
        recorder.snapshot()
    }

    public func pause() {
        if state == .running {
            state = .paused
        }
    }

    public func resume() {
        if state == .paused {
            state = .running
        }
    }

    public func requestStop() async {
        await sovereignty.requestStop()
        if state == .running || state == .paused || state == .arming {
            state = .stopping
        }
    }

    /// Runs a workflow to completion (or stop/error). Deterministic under a fake clock.
    public func run(_ workflow: Workflow) async {
        guard state == .idle else { return }
        guard let target = workflow.targets.first else {
            state = .error("workflow has no targets")
            await transitionToIdleViaStopping()
            return
        }

        state = .arming
        state = .running
        iterationsCompleted = 0
        let runStarted = timing.clock.now

        let maxIterations: Int
        if workflow.loop.enabled {
            maxIterations = max(1, workflow.loop.maxIterations)
        } else {
            maxIterations = 1
        }

        outer: for iteration in 1...maxIterations {
            if await sovereignty.shouldHalt() {
                state = .stopping
                break
            }
            if let maxDuration = workflow.loop.maxDurationSeconds {
                let elapsed = timing.clock.now.timeIntervalSince(runStarted)
                if elapsed >= maxDuration {
                    break
                }
            }

            for step in workflow.steps {
                if state == .stopping || state == .paused {
                    if state == .paused {
                        // Wait until resumed or halt (tests resume synchronously).
                        while state == .paused {
                            if await sovereignty.shouldHalt() {
                                state = .stopping
                                break outer
                            }
                            await Task.yield()
                        }
                    }
                    if state == .stopping {
                        break outer
                    }
                }

                if await sovereignty.shouldHalt() {
                    state = .stopping
                    break outer
                }

                let outcome = await executeStep(step, target: target)
                switch outcome {
                case .aborted:
                    state = .error("step aborted")
                    break outer
                case .completed, .skipped, .denied, .failed:
                    continue
                }
            }

            iterationsCompleted = iteration

            if !workflow.loop.enabled {
                break
            }
        }

        await transitionToIdleViaStopping()
    }

    private func transitionToIdleViaStopping() async {
        switch state {
        case .idle:
            return
        case .error:
            state = .stopping
            state = .idle
        case .stopping, .running, .paused, .arming:
            state = .stopping
            state = .idle
        }
    }

    private func executeStep(_ step: Step, target: TargetApp) async -> StepOutcome {
        lastStepPhase = .pending
        var retriesLeft = step.retryPolicy.maxRetries

        while true {
            lastStepPhase = .validating
            let decision = safety.validate(action: step.action, target: target)
            switch decision {
            case .deny(let reason):
                record(action: step.action, target: target, result: .denied)
                _ = reason
                lastStepPhase = .failed
                let outcome = StepLifecycle.nextAction(onError: step.onError, retriesRemaining: retriesLeft)
                if outcome == .failed && retriesLeft > 0 {
                    retriesLeft -= 1
                    continue
                }
                if step.onError == .skip {
                    record(action: step.action, target: target, result: .skipped)
                    lastStepPhase = .completed
                    return .skipped
                }
                return outcome == .aborted ? .aborted : .denied

            case .allow:
                break
            }

            lastStepPhase = .executing
            do {
                if case .wait(let seconds) = step.action {
                    let start = timing.clock.now
                    _ = await timing.wait(timeoutSeconds: seconds) {
                        timing.clock.now.timeIntervalSince(start) >= seconds
                    }
                } else {
                    try await executor.execute(action: step.action, target: target)
                }
                lastStepPhase = .settling
                let settleStart = timing.clock.now
                _ = await timing.wait(timeoutSeconds: 0.01) {
                    timing.clock.now.timeIntervalSince(settleStart) >= 0.01
                }
                lastStepPhase = .completed
                record(action: step.action, target: target, result: .completed)
                return .completed
            } catch {
                lastStepPhase = .failed
                record(action: step.action, target: target, result: .failed)
                let outcome = StepLifecycle.nextAction(onError: step.onError, retriesRemaining: retriesLeft)
                if outcome == .failed && retriesLeft > 0 {
                    retriesLeft -= 1
                    continue
                }
                if step.onError == .skip {
                    record(action: step.action, target: target, result: .skipped)
                    lastStepPhase = .completed
                    return .skipped
                }
                return .aborted
            }
        }
    }

    private func record(action: ActionKind, target: TargetApp, result: RunEventResult) {
        recorder.append(
            RunEvent(
                timestamp: timing.clock.now,
                actionKind: ActionKindLabel.label(for: action),
                targetBundleID: target.bundleID,
                result: result
            )
        )
    }
}
