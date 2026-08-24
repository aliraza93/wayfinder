import Domain
import Foundation
import Observability
import Safety

/// Sequencer / state machine. Routes every action through `SafetyPolicy` before execution.
/// Recovery: TOCTOU probe, capped retries, typed errors, focus restore at stop.
public actor WorkflowEngine {
    public private(set) var state: EngineState = .idle
    public private(set) var lastStepPhase: StepPhase = .pending
    public private(set) var iterationsCompleted: Int = 0
    /// Last recovery message (content-free), e.g. "couldn't restore focus".
    public private(set) var lastRecoveryMessage: String?
    public private(set) var focusRestoreResult: FocusRestoreResult?

    private let safety: SafetyPolicy
    private let executor: ActionExecutor
    private let sovereignty: UserSovereigntySignal
    private let timing: TimingPolicy
    private let recorder: RunRecorder
    private let preconditionProbe: any RunPreconditionProbe
    private let focusRestorer: any FocusRestorer

    public init(
        safety: SafetyPolicy = SafetyPolicy(),
        executor: ActionExecutor,
        sovereignty: UserSovereigntySignal,
        timing: TimingPolicy,
        recorder: RunRecorder = RunRecorder(),
        preconditionProbe: any RunPreconditionProbe = AlwaysReadyProbe(),
        focusRestorer: any FocusRestorer = NullFocusRestorer()
    ) {
        self.safety = safety
        self.executor = executor
        self.sovereignty = sovereignty
        self.timing = timing
        self.recorder = recorder
        self.preconditionProbe = preconditionProbe
        self.focusRestorer = focusRestorer
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
        lastRecoveryMessage = nil
        focusRestoreResult = nil

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
                    if lastRecoveryMessage == nil {
                        state = .error("step aborted")
                    } else {
                        state = .error(lastRecoveryMessage!)
                    }
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

        await finishWithFocusRestore(targetBundleID: target.bundleID)
    }

    private func finishWithFocusRestore(targetBundleID: String) async {
        let restore = await focusRestorer.restoreFocus(to: targetBundleID)
        focusRestoreResult = restore
        switch restore {
        case .restored:
            recordMeta(actionKind: "focusRestore", targetBundleID: targetBundleID, result: .completed)
        case .couldNotRestore:
            lastRecoveryMessage = "couldn't restore focus"
            recordMeta(actionKind: "focusRestore", targetBundleID: targetBundleID, result: .failed)
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
        var retriesLeft = Recovery.cappedRetries(requested: step.retryPolicy.maxRetries)

        while true {
            lastStepPhase = .validating
            let decision = safety.validate(action: step.action, target: target)
            switch decision {
            case .deny(let reason):
                // Forbidden — never swallow, never skip/retry past the safety gate.
                record(action: step.action, target: target, result: .denied)
                lastStepPhase = .failed
                lastRecoveryMessage = reason
                await sovereignty.noteUserIntervention()
                return .aborted

            case .allow:
                break
            }

            lastStepPhase = .executing
            do {
                if case .wait(let seconds) = step.action {
                    let start = timing.clock.now
                    let budget = min(seconds, step.timeoutSeconds)
                    let finished = await timing.wait(timeoutSeconds: budget) {
                        timing.clock.now.timeIntervalSince(start) >= seconds
                    }
                    if !finished {
                        throw TimeoutError("wait exceeded timeout (\(step.timeoutSeconds)s)")
                    }
                } else {
                    // TOCTOU: re-assert focus / permission immediately before the event.
                    try await preconditionProbe.assertReady(for: target)
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
                let kind = Recovery.classify(error)
                lastRecoveryMessage = kind.message
                record(action: step.action, target: target, result: .failed)

                if kind.mustAbort {
                    // Permission / forbidden — stop immediately; never skip.
                    await sovereignty.noteUserIntervention()
                    return .aborted
                }

                if case .precondition = kind {
                    // Focus change / Secure Input / AX loss → treat as intervention → stop.
                    await sovereignty.noteUserIntervention()
                    return .aborted
                }

                if Recovery.shouldRetry(kind: kind, onError: step.onError, retriesRemaining: retriesLeft) {
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
        recordMeta(
            actionKind: ActionKindLabel.label(for: action),
            targetBundleID: target.bundleID,
            result: result
        )
    }

    private func recordMeta(actionKind: String, targetBundleID: String, result: RunEventResult) {
        recorder.append(
            RunEvent(
                timestamp: timing.clock.now,
                actionKind: actionKind,
                targetBundleID: targetBundleID,
                result: result
            )
        )
    }
}
