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
    public private(set) var endReason: RunEndReason?
    public private(set) var runStartedAt: Date?
    public private(set) var configuredDurationSeconds: Double?
    public private(set) var currentActionKind: String?
    /// Live Universal Workspace Navigation dashboard fields (identity only — never body text).
    public private(set) var currentReviewIdentity: String?
    public private(set) var nextReviewIdentity: String?
    public private(set) var reviewTargetsCompleted: Int = 0
    public private(set) var currentDwellElapsedSeconds: Double?
    public private(set) var currentDwellAllocatedSeconds: Double?
    public private(set) var reviewUIPhase: String = "idle"
    public private(set) var discoverySummary: String = ""

    /// Frontmost workflow target for the current step (updated by activate / return).
    private var activeTarget: TargetApp?
    /// Stack of prior targets for `returnToPrevious`.
    private var returnStack: [TargetApp] = []
    /// All configured targets for this run (lookup by bundle id).
    private var knownTargets: [TargetApp] = []

    private let safety: SafetyPolicy
    private let executor: ActionExecutor
    private let sovereignty: UserSovereigntySignal
    private let timing: TimingPolicy
    private let recorder: RunRecorder
    private let preconditionProbe: any RunPreconditionProbe
    private let focusRestorer: any FocusRestorer
    private let discoverySource: any ApplicationDiscoverySource

    public init(
        safety: SafetyPolicy = SafetyPolicy(),
        executor: ActionExecutor,
        sovereignty: UserSovereigntySignal,
        timing: TimingPolicy,
        recorder: RunRecorder = RunRecorder(),
        preconditionProbe: any RunPreconditionProbe = AlwaysReadyProbe(),
        focusRestorer: any FocusRestorer = NullFocusRestorer(),
        discoverySource: any ApplicationDiscoverySource = EmptyApplicationDiscovery()
    ) {
        self.safety = safety
        self.executor = executor
        self.sovereignty = sovereignty
        self.timing = timing
        self.recorder = recorder
        self.preconditionProbe = preconditionProbe
        self.focusRestorer = focusRestorer
        self.discoverySource = discoverySource
    }

    public func runEvents() -> [RunEvent] {
        recorder.snapshot()
    }

    public func pause() {
        guard state == .running else { return }
        state = .paused
        recordMeta(
            actionKind: "pause",
            targetBundleID: "",
            result: .completed
        )
    }

    public func resume() {
        guard state == .paused else { return }
        state = .running
        recordMeta(
            actionKind: "resume",
            targetBundleID: "",
            result: .completed
        )
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
        endReason = nil
        currentActionKind = nil
        configuredDurationSeconds = workflow.loop.maxDurationSeconds

        guard let target = workflow.targets.first else {
            state = .error("workflow has no targets")
            endReason = .failed
            recordMeta(actionKind: "runFailed", targetBundleID: "", result: .failed)
            await transitionToIdleViaStopping()
            return
        }

        knownTargets = workflow.targets
        activeTarget = target
        returnStack = []

        state = .arming
        state = .running
        iterationsCompleted = 0
        let runStarted = timing.clock.now
        runStartedAt = runStarted
        recordMeta(actionKind: "runStarted", targetBundleID: target.bundleID, result: .completed)
        recordMeta(actionKind: "targetDetected", targetBundleID: target.bundleID, result: .completed)

        let maxIterations = Self.resolvedMaxIterations(for: workflow.loop)
        let shouldContinueLooping =
            workflow.loop.enabled
            || workflow.loop.untilStopped
            || workflow.loop.maxDurationSeconds != nil

        var stoppedByUser = false
        var failed = false

        outer: for iteration in 1...maxIterations {
            if await sovereignty.shouldHalt() {
                state = .stopping
                stoppedByUser = true
                break
            }
            if let maxDuration = workflow.loop.maxDurationSeconds {
                let elapsed = timing.clock.now.timeIntervalSince(runStarted)
                if elapsed >= maxDuration {
                    break
                }
            }

            let stepsThisRound: [Step]
            // Timed / until-stopped runs always use the universal multi-target session.
            // Do not gate on shuffleSteps — older saves omitted it (defaulted false) and
            // never left Cursor for Chrome.
            let useUniversalSession =
                workflow.loop.maxDurationSeconds != nil || workflow.loop.untilStopped

            if useUniversalSession {
                stepsThisRound = [] // unused; handled below
            } else if workflow.loop.shuffleSteps, workflow.steps.count > 1 {
                stepsThisRound = workflow.steps.shuffled()
            } else {
                stepsThisRound = workflow.steps
            }

            if useUniversalSession {
                var reviewSettings = workflow.review
                if reviewSettings.filePaths.isEmpty, !workflow.reviewFilePaths.isEmpty {
                    reviewSettings.filePaths = workflow.reviewFilePaths
                }
                let initialDiscovery = reviewSettings.discoverRunningApps
                    ? discoverySource.discoverApplications()
                    : []
                if reviewSettings.discoverRunningApps {
                    mergeDiscoveredIntoKnown(initialDiscovery)
                }
                var controller = TimedReviewNavigation.makeController(
                    settings: reviewSettings,
                    targets: knownTargets,
                    discovered: initialDiscovery
                )
                discoverySummary = Self.formatDiscovery(controller.discoveryCounts)
                reviewUIPhase = "discovering"
                recordMeta(
                    actionKind: "applicationsDiscovered",
                    targetBundleID: target.bundleID,
                    result: .completed,
                    identity: "\(initialDiscovery.count) apps"
                )
                recordMeta(
                    actionKind: "targetsDiscovered",
                    targetBundleID: target.bundleID,
                    result: .completed,
                    identity: "\(controller.queue.count) targets"
                )
                reviewUIPhase = "running"
                recordMeta(
                    actionKind: "workflowStarted",
                    targetBundleID: target.bundleID,
                    result: .completed,
                    identity: workflow.name
                )
                while true {
                    if state == .stopping || state == .paused {
                        if state == .paused {
                            reviewUIPhase = "paused"
                            recordMeta(actionKind: "workflowPaused", targetBundleID: activeTarget?.bundleID ?? "", result: .completed)
                            while state == .paused {
                                if await sovereignty.shouldHalt() {
                                    state = .stopping
                                    stoppedByUser = true
                                    break outer
                                }
                                let pausePoll = timing.clock.now
                                _ = await timing.wait(timeoutSeconds: 0.05) {
                                    timing.clock.now.timeIntervalSince(pausePoll) >= 0.05
                                }
                                if state != .paused { break }
                            }
                            if state == .running {
                                reviewUIPhase = "running"
                                recordMeta(actionKind: "workflowResumed", targetBundleID: activeTarget?.bundleID ?? "", result: .completed)
                            }
                        }
                        if state == .stopping {
                            stoppedByUser = true
                            break outer
                        }
                    }
                    if await sovereignty.shouldHalt() {
                        state = .stopping
                        stoppedByUser = true
                        break outer
                    }
                    if let maxDuration = workflow.loop.maxDurationSeconds {
                        let elapsed = timing.clock.now.timeIntervalSince(runStarted)
                        if elapsed >= maxDuration {
                            break outer
                        }
                    }

                    if controller.recordMetaCompleted {
                        recordMeta(
                            actionKind: "targetCompleted",
                            targetBundleID: activeTarget?.bundleID ?? "",
                            result: .completed,
                            identity: controller.completedIdentity ?? controller.current?.identity
                        )
                        controller.recordMetaCompleted = false
                        controller.completedIdentity = nil
                    }

                    if controller.needsDiscoveryRefresh {
                        reviewUIPhase = "refreshing"
                        let refreshed = reviewSettings.discoverRunningApps
                            ? discoverySource.discoverApplications()
                            : []
                        if reviewSettings.discoverRunningApps {
                            mergeDiscoveredIntoKnown(refreshed)
                        }
                        controller.applyDiscoveryRefresh(
                            discovered: refreshed,
                            workflowTargets: knownTargets
                        )
                        discoverySummary = Self.formatDiscovery(controller.discoveryCounts)
                        recordMeta(
                            actionKind: "targetsRefreshed",
                            targetBundleID: activeTarget?.bundleID ?? "",
                            result: .completed,
                            identity: "\(controller.queue.count) targets"
                        )
                        reviewUIPhase = "running"
                        continue
                    }

                    guard let pick = controller.nextPick(now: timing.clock.now) else {
                        break outer
                    }

                    let isActivate: Bool
                    if case .activateApp = pick.action {
                        isActivate = true
                        reviewUIPhase = "switchingTarget"
                    } else {
                        isActivate = false
                    }

                    currentReviewIdentity = controller.current?.identity ?? pick.identity
                    nextReviewIdentity = controller.nextPreview?.identity
                    reviewTargetsCompleted = controller.targetsCompleted
                    currentDwellAllocatedSeconds = controller.dwellAllocatedSeconds
                    if let start = controller.dwellStartedAt {
                        currentDwellElapsedSeconds = timing.clock.now.timeIntervalSince(start)
                    }

                    if let meta = pick.metaKind {
                        recordMeta(
                            actionKind: meta,
                            targetBundleID: activeTarget?.bundleID ?? target.bundleID,
                            result: .completed,
                            identity: pick.identity
                        )
                    }

                    let step = Step(
                        action: pick.action,
                        timeoutSeconds: isActivate ? 10 : 4,
                        retryPolicy: RetryPolicy(maxRetries: isActivate ? 2 : 0),
                        onError: .skip
                    )
                    currentActionKind = ActionKindLabel.label(for: step.action)
                    reviewUIPhase = "running"
                    let outcome = await executeStep(
                        step,
                        runStarted: runStarted,
                        maxDurationSeconds: workflow.loop.maxDurationSeconds,
                        interActionGap: pick.gapSeconds
                    )
                    switch outcome {
                    case .aborted:
                        failed = true
                        reviewUIPhase = "failed"
                        if lastRecoveryMessage == nil {
                            state = .error("step aborted")
                        } else {
                            state = .error(lastRecoveryMessage!)
                        }
                        break outer
                    case .skipped, .denied, .failed:
                        if isActivate {
                            recordMeta(
                                actionKind: "activateFailedAdvance",
                                targetBundleID: activeTarget?.bundleID ?? "",
                                result: .failed,
                                identity: pick.identity
                            )
                            // Do not crawl the wrong app — jump to the next allowlisted target.
                            controller.abandonCurrentTarget(now: timing.clock.now)
                        }
                        continue
                    case .completed:
                        continue
                    }
                }
            } else {
            for step in stepsThisRound {
                if state == .stopping || state == .paused {
                    if state == .paused {
                        while state == .paused {
                            if await sovereignty.shouldHalt() {
                                state = .stopping
                                stoppedByUser = true
                                break outer
                            }
                            let pausePoll = timing.clock.now
                            _ = await timing.wait(timeoutSeconds: 0.05) {
                                timing.clock.now.timeIntervalSince(pausePoll) >= 0.05
                            }
                            if state != .paused { break }
                        }
                    }
                    if state == .stopping {
                        stoppedByUser = true
                        break outer
                    }
                }

                if await sovereignty.shouldHalt() {
                    state = .stopping
                    stoppedByUser = true
                    break outer
                }

                if let maxDuration = workflow.loop.maxDurationSeconds {
                    let elapsed = timing.clock.now.timeIntervalSince(runStarted)
                    if elapsed >= maxDuration {
                        break outer
                    }
                }

                currentActionKind = ActionKindLabel.label(for: step.action)
                let outcome = await executeStep(
                    step,
                    runStarted: runStarted,
                    maxDurationSeconds: workflow.loop.maxDurationSeconds
                )
                switch outcome {
                case .aborted:
                    failed = true
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
            } // end sequential / universal session

            iterationsCompleted = iteration

            if useUniversalSession || !shouldContinueLooping {
                break
            }
        }

        if failed {
            endReason = .failed
            recordMeta(actionKind: "runFailed", targetBundleID: target.bundleID, result: .failed)
        } else if stoppedByUser || state == .stopping {
            endReason = .stopped
            recordMeta(actionKind: "runStopped", targetBundleID: target.bundleID, result: .completed)
        } else {
            endReason = .completed
            recordMeta(actionKind: "runCompleted", targetBundleID: target.bundleID, result: .completed)
        }

        currentActionKind = nil
        await finishWithFocusRestore(targetBundleID: target.bundleID)
    }

    public static func resolvedMaxIterations(for loop: LoopSettings) -> Int {
        // Duration / until-stopped own the stop condition — do not let a low UI
        // "safety ceiling" end a timed run after one pass.
        if loop.untilStopped || loop.maxDurationSeconds != nil {
            return NavigationLimits.absoluteMaxIterations
        }
        if loop.enabled {
            return min(max(1, loop.maxIterations), NavigationLimits.absoluteMaxIterations)
        }
        return 1
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

    private func executeStep(
        _ step: Step,
        runStarted: Date,
        maxDurationSeconds: Double?,
        interActionGap: Double? = nil
    ) async -> StepOutcome {
        guard var target = activeTarget else {
            lastRecoveryMessage = "no active target"
            return .aborted
        }

        lastStepPhase = .pending
        var retriesLeft = Recovery.cappedRetries(requested: step.retryPolicy.maxRetries)

        while true {
            lastStepPhase = .validating
            let decision = safety.validate(action: step.action, target: target)
            switch decision {
            case .deny(let reason):
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
                    lastStepPhase = .completed
                    record(action: step.action, target: target, result: .completed)
                    return .completed
                } else if case .returnToPrevious = step.action {
                    guard let previous = returnStack.popLast() else {
                        record(action: step.action, target: target, result: .skipped)
                        lastStepPhase = .completed
                        return .skipped
                    }
                    let activate = ActionKind.activateApp(bundleID: previous.bundleID)
                    try await executor.execute(action: activate, target: previous)
                    activeTarget = previous
                    target = previous
                    lastStepPhase = .completed
                    record(action: step.action, target: previous, result: .completed)
                    return .completed
                } else if case .activateApp(let bundleID) = step.action {
                    let destinationID = bundleID.isEmpty ? target.bundleID : bundleID
                    let destination = resolveKnownTarget(bundleID: destinationID)
                    let activate = ActionKind.activateApp(bundleID: destination.bundleID)
                    try await executor.execute(action: activate, target: destination)
                    if destination.bundleID != target.bundleID {
                        returnStack.append(target)
                    }
                    activeTarget = destination
                    target = destination
                    lastStepPhase = .completed
                    record(action: activate, target: destination, result: .completed)
                    return .completed
                } else if case .openExistingFile(let path) = step.action {
                    // File opens always go through an editor target when one is configured.
                    var openTarget = target
                    if target.classification != .editor,
                       let editor = knownTargets.first(where: { $0.classification == .editor })
                    {
                        let activate = ActionKind.activateApp(bundleID: editor.bundleID)
                        try await executor.execute(action: activate, target: editor)
                        if editor.bundleID != target.bundleID {
                            returnStack.append(target)
                        }
                        activeTarget = editor
                        openTarget = editor
                        target = editor
                        record(action: activate, target: editor, result: .completed)
                    }
                    let open = ActionKind.openExistingFile(path: path)
                    try await executor.execute(action: open, target: openTarget)
                    lastStepPhase = .completed
                    record(action: open, target: openTarget, result: .completed)
                    return .completed
                } else if case .arrowNavigate(let direction, let presses, let intervalSeconds) = step.action {
                    let count = min(max(1, presses), NavigationLimits.maxArrowPresses)
                    let interval = intervalSeconds > 0
                        ? min(max(intervalSeconds, NavigationLimits.minIntervalSeconds), NavigationLimits.maxIntervalSeconds)
                        : (interActionGap ?? 0)
                    for index in 0..<count {
                        if await sovereignty.shouldHalt() {
                            await sovereignty.noteUserIntervention()
                            return .aborted
                        }
                        if let maxDuration = maxDurationSeconds {
                            let elapsed = timing.clock.now.timeIntervalSince(runStarted)
                            if elapsed >= maxDuration {
                                lastStepPhase = .completed
                                return .completed
                            }
                        }
                        let single = ActionKind.arrowNavigate(
                            direction: direction,
                            presses: 1,
                            intervalSeconds: 0
                        )
                        try await assertReadyIfNeeded(for: single, target: target)
                        try await executor.execute(action: single, target: target)
                        record(action: single, target: target, result: .completed)
                        let gap: Double
                        if index + 1 < count {
                            gap = interval
                        } else {
                            gap = interActionGap ?? 0
                        }
                        if gap > 0 {
                            let waitStart = timing.clock.now
                            _ = await timing.wait(timeoutSeconds: gap) {
                                timing.clock.now.timeIntervalSince(waitStart) >= gap
                            }
                        }
                    }
                    lastStepPhase = .completed
                    return .completed
                } else {
                    try await assertReadyIfNeeded(for: step.action, target: target)
                    try await executor.execute(action: step.action, target: target)
                    let gap = interActionGap ?? 0.01
                    if gap > 0 {
                        let settleStart = timing.clock.now
                        _ = await timing.wait(timeoutSeconds: gap) {
                            timing.clock.now.timeIntervalSince(settleStart) >= gap
                        }
                    }
                    lastStepPhase = .completed
                    record(action: step.action, target: target, result: .completed)
                    return .completed
                }
            } catch {
                lastStepPhase = .failed
                let kind = Recovery.classify(error)
                lastRecoveryMessage = kind.message
                record(action: step.action, target: target, result: .failed)

                if kind.mustAbort {
                    await sovereignty.noteUserIntervention()
                    return .aborted
                }

                if case .precondition = kind {
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

    private func assertReadyIfNeeded(for action: ActionKind, target: TargetApp) async throws {
        guard action.capabilityTags.requiresFocusGuard else { return }
        try await preconditionProbe.assertReady(for: target)
    }

    private func resolveKnownTarget(bundleID: String) -> TargetApp {
        if let known = knownTargets.first(where: { $0.bundleID == bundleID }) {
            return known
        }
        let classified = TargetApp(
            bundleID: bundleID,
            classification: ApplicationClassifier.classify(bundleID: bundleID)
        )
        knownTargets.append(classified)
        return classified
    }

    private func mergeDiscoveredIntoKnown(_ apps: [DiscoveredApplication]) {
        for app in apps {
            if knownTargets.contains(where: { $0.bundleID == app.bundleID }) { continue }
            knownTargets.append(
                TargetApp(bundleID: app.bundleID, classification: app.classification)
            )
        }
    }

    private static func formatDiscovery(_ counts: [String: Int]) -> String {
        counts
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: ", ")
    }

    private func record(action: ActionKind, target: TargetApp, result: RunEventResult) {
        recordMeta(
            actionKind: ActionKindLabel.label(for: action),
            targetBundleID: target.bundleID,
            result: result
        )
    }

    private func recordMeta(
        actionKind: String,
        targetBundleID: String,
        result: RunEventResult,
        identity: String? = nil
    ) {
        recorder.append(
            RunEvent(
                timestamp: timing.clock.now,
                actionKind: actionKind,
                targetBundleID: targetBundleID,
                result: result,
                identity: identity
            )
        )
    }
}
