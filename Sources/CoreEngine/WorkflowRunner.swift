import Adapters
import Config
import Domain
import Foundation
import Observability
import Safety

public enum WorkflowRunnerError: Error, Equatable, Sendable {
    case workflowNotFound(String)
    case validationFailed(String)
    case safetyDenied(String)
    case targetUnavailable(bundleID: String)
    case noTargets
}

/// Injectable “is this bundle currently available” check (AppControl in production).
public protocol WorkflowTargetResolver: Sendable {
    func isAvailable(bundleID: String) -> Bool
}

/// CI / offline: every configured target is treated as available.
public struct PermissiveTargetResolver: WorkflowTargetResolver {
    public init() {}
    public func isAvailable(bundleID: String) -> Bool {
        _ = bundleID
        return true
    }
}

public struct PreparedWorkflow: Equatable, Sendable {
    public var workflow: Workflow
    public var adapterByBundleID: [String: ResolvedAdapter]

    public init(workflow: Workflow, adapterByBundleID: [String: ResolvedAdapter]) {
        self.workflow = workflow
        self.adapterByBundleID = adapterByBundleID
    }
}

public struct WorkflowRunSummary: Equatable, Sendable {
    public var workflowName: String
    public var events: [RunEvent]
    public var adapters: [String: ResolvedAdapter]
    public var endReason: RunEndReason?

    public init(
        workflowName: String,
        events: [RunEvent],
        adapters: [String: ResolvedAdapter],
        endReason: RunEndReason? = nil
    ) {
        self.workflowName = workflowName
        self.events = events
        self.adapters = adapters
        self.endReason = endReason
    }
}

/// Loads → validates → resolves targets → selects adapters → runs on `WorkflowEngine`.
/// Does not bypass `WorkflowValidator` or `SafetyPolicy`.
public actor WorkflowRunner {
    private let store: ConfigStore
    private let configValidator: WorkflowValidator
    private let safety: SafetyPolicy

    public init(
        store: ConfigStore,
        configValidator: WorkflowValidator = WorkflowValidator(),
        safety: SafetyPolicy = SafetyPolicy()
    ) {
        self.store = store
        self.configValidator = configValidator
        self.safety = safety
    }

    public func listWorkflowNames() throws -> [String] {
        try store.load().workflows.map(\.name)
    }

    public func loadDocument() throws -> WorkflowConfigDocument {
        try store.load()
    }

    /// Writes a sample multi-target document when `workflows.json` is missing.
    public func ensureDefaultDocumentIfMissing(
        _ document: WorkflowConfigDocument = WorkflowRunner.sampleMultiTargetDocument()
    ) throws {
        let url = store.workflowsFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            return
        }
        try store.save(document)
    }

    /// Validate + resolve + adapter-select + rewrite. Throws before any execution.
    public func prepare(
        workflowName: String,
        resolver: any WorkflowTargetResolver
    ) throws -> PreparedWorkflow {
        let document = try store.load()
        guard let workflow = document.workflows.first(where: { $0.name == workflowName }) else {
            throw WorkflowRunnerError.workflowNotFound(workflowName)
        }
        return try prepare(workflow: workflow, resolver: resolver)
    }

    public func prepare(
        workflow: Workflow,
        resolver: any WorkflowTargetResolver
    ) throws -> PreparedWorkflow {
        do {
            try configValidator.validate(workflow)
        } catch {
            throw WorkflowRunnerError.validationFailed(String(describing: error))
        }

        guard !workflow.targets.isEmpty else {
            throw WorkflowRunnerError.noTargets
        }

        for target in workflow.targets {
            guard resolver.isAvailable(bundleID: target.bundleID) else {
                throw WorkflowRunnerError.targetUnavailable(bundleID: target.bundleID)
            }
        }

        for step in workflow.steps {
            for target in workflow.targets {
                switch safety.validate(action: step.action, target: target) {
                case .allow:
                    continue
                case .deny(let reason):
                    throw WorkflowRunnerError.safetyDenied(reason)
                }
            }
        }

        var adapters: [String: ResolvedAdapter] = [:]
        for target in workflow.targets {
            adapters[target.bundleID] = AdapterResolver.resolve(target)
        }

        // Engine executes against the primary (first) target; rewrite steps for that adapter.
        let primary = workflow.targets[0]
        let kind = adapters[primary.bundleID] ?? .generic
        let rewrittenSteps = NavigationStepExpander.expand(
            workflow.steps.map { step -> Step in
                let action = AdapterActionMapper.rewrite(step.action, target: primary, adapter: kind)
                return Step(
                    action: action,
                    timeoutSeconds: step.timeoutSeconds,
                    retryPolicy: step.retryPolicy,
                    onError: step.onError
                )
            }
        )

        let prepared = Workflow(
            name: workflow.name,
            targets: workflow.targets,
            steps: rewrittenSteps,
            loop: workflow.loop,
            reviewFilePaths: workflow.reviewFilePaths,
            review: workflow.review
        )
        return PreparedWorkflow(workflow: prepared, adapterByBundleID: adapters)
    }

    /// Full path: prepare then run on the engine. Invalid workflows never reach the executor.
    /// When `engineHandler` is provided, it receives the live engine before `run` (for pause/UI).
    public func run(
        workflowName: String,
        executor: ActionExecutor,
        sovereignty: UserSovereigntySignal,
        timing: TimingPolicy,
        recorder: RunRecorder = RunRecorder(),
        resolver: any WorkflowTargetResolver = PermissiveTargetResolver(),
        preconditionProbe: any RunPreconditionProbe = AlwaysReadyProbe(),
        discoverySource: any ApplicationDiscoverySource = EmptyApplicationDiscovery(),
        pageInspectionSource: any WebPageInspectionSource = EmptyWebPageInspection(),
        engineHandler: ((WorkflowEngine) async -> Void)? = nil
    ) async throws -> WorkflowRunSummary {
        let prepared = try prepare(workflowName: workflowName, resolver: resolver)
        let engine = WorkflowEngine(
            safety: safety,
            executor: executor,
            sovereignty: sovereignty,
            timing: timing,
            recorder: recorder,
            preconditionProbe: preconditionProbe,
            discoverySource: discoverySource,
            pageInspectionSource: pageInspectionSource
        )
        if let engineHandler {
            await engineHandler(engine)
        }
        await engine.run(prepared.workflow)
        let reason = await engine.endReason
        return WorkflowRunSummary(
            workflowName: prepared.workflow.name,
            events: recorder.snapshot(),
            adapters: prepared.adapterByBundleID,
            endReason: reason
        )
    }

    public func run(
        workflow: Workflow,
        executor: ActionExecutor,
        sovereignty: UserSovereigntySignal,
        timing: TimingPolicy,
        recorder: RunRecorder = RunRecorder(),
        resolver: any WorkflowTargetResolver = PermissiveTargetResolver(),
        preconditionProbe: any RunPreconditionProbe = AlwaysReadyProbe(),
        discoverySource: any ApplicationDiscoverySource = EmptyApplicationDiscovery(),
        pageInspectionSource: any WebPageInspectionSource = EmptyWebPageInspection(),
        engineHandler: ((WorkflowEngine) async -> Void)? = nil
    ) async throws -> WorkflowRunSummary {
        let prepared = try prepare(workflow: workflow, resolver: resolver)
        let engine = WorkflowEngine(
            safety: safety,
            executor: executor,
            sovereignty: sovereignty,
            timing: timing,
            recorder: recorder,
            preconditionProbe: preconditionProbe,
            discoverySource: discoverySource,
            pageInspectionSource: pageInspectionSource
        )
        if let engineHandler {
            await engineHandler(engine)
        }
        await engine.run(prepared.workflow)
        let reason = await engine.endReason
        return WorkflowRunSummary(
            workflowName: prepared.workflow.name,
            events: recorder.snapshot(),
            adapters: prepared.adapterByBundleID,
            endReason: reason
        )
    }

    /// Sample multi-target JSON-friendly workflow for seeding / CI.
    public static func sampleMultiTargetDocument() -> WorkflowConfigDocument {
        WorkflowConfigDocument(
            schemaVersion: SchemaVersion.current,
            workflows: [
                Workflow(
                    name: "multi-target-scroll",
                    targets: [
                        TargetApp(bundleID: "com.google.Chrome", classification: .browser),
                        TargetApp(bundleID: "com.microsoft.VSCode", classification: .editor),
                        TargetApp(bundleID: "com.apple.finder", classification: .finder),
                    ],
                    steps: [
                        Step(
                            action: .scroll(direction: .down, amount: 40),
                            timeoutSeconds: 2,
                            retryPolicy: RetryPolicy(maxRetries: 0),
                            onError: .abort
                        ),
                        Step(
                            action: .wait(seconds: 0.2),
                            timeoutSeconds: 1,
                            retryPolicy: RetryPolicy(maxRetries: 0),
                            onError: .abort
                        ),
                        Step(
                            action: .pageNavigate(.pageDown),
                            timeoutSeconds: 2,
                            retryPolicy: RetryPolicy(maxRetries: 0),
                            onError: .skip
                        ),
                        Step(
                            action: .scroll(direction: .up, amount: 40),
                            timeoutSeconds: 2,
                            retryPolicy: RetryPolicy(maxRetries: 0),
                            onError: .abort
                        ),
                    ],
                    loop: LoopSettings(enabled: true, maxIterations: 2, maxDurationSeconds: nil)
                ),
            ]
        )
    }
}
