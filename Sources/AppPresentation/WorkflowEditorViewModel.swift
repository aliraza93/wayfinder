import Config
import Domain
import Foundation
import Safety

/// Editable draft of a workflow. Validation uses Config + Safety — illegal steps cannot save.
public struct WorkflowDraft: Equatable, Sendable {
    public var name: String
    public var targets: [TargetApp]
    public var steps: [Step]
    public var loopEnabled: Bool
    public var maxIterations: Int
    public var maxDurationSeconds: Double?

    public init(
        name: String = "Untitled",
        targets: [TargetApp] = [],
        steps: [Step] = [],
        loopEnabled: Bool = false,
        maxIterations: Int = 1,
        maxDurationSeconds: Double? = nil
    ) {
        self.name = name
        self.targets = targets
        self.steps = steps
        self.loopEnabled = loopEnabled
        self.maxIterations = maxIterations
        self.maxDurationSeconds = maxDurationSeconds
    }

    public init(workflow: Workflow) {
        self.name = workflow.name
        self.targets = workflow.targets
        self.steps = workflow.steps
        self.loopEnabled = workflow.loop.enabled
        self.maxIterations = workflow.loop.maxIterations
        self.maxDurationSeconds = workflow.loop.maxDurationSeconds
    }

    public func asWorkflow() -> Workflow {
        Workflow(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            targets: targets,
            steps: steps,
            loop: LoopSettings(
                enabled: loopEnabled,
                maxIterations: max(1, maxIterations),
                maxDurationSeconds: maxDurationSeconds
            )
        )
    }
}

public enum WorkflowEditorError: Error, Equatable, Sendable {
    case emptyName
    case noTargets
    case noSteps
    case validation(String)
    case safety(String)
    case saveFailed(String)
}

/// View-model logic for composing workflows. No SwiftUI.
public final class WorkflowEditorViewModel: @unchecked Sendable {
    public private(set) var draft: WorkflowDraft
    public private(set) var lastError: String?
    public private(set) var runningApps: [(bundleID: String, displayName: String)]
    /// Friendly names keyed by bundle ID (not persisted in config schema).
    public private(set) var targetDisplayNames: [String: String] = [:]

    private let store: ConfigStore
    private let validator: WorkflowValidator
    private let safety: SafetyPolicy
    private let listRunning: () -> [(bundleID: String, displayName: String)]

    public init(
        store: ConfigStore,
        draft: WorkflowDraft = WorkflowDraft(),
        validator: WorkflowValidator = WorkflowValidator(),
        safety: SafetyPolicy = SafetyPolicy(),
        listRunning: @escaping () -> [(bundleID: String, displayName: String)] = { [] }
    ) {
        self.store = store
        self.draft = draft
        self.validator = validator
        self.safety = safety
        self.listRunning = listRunning
        self.runningApps = listRunning()
        for app in runningApps {
            targetDisplayNames[app.bundleID] = app.displayName
        }
    }

    public func refreshRunningApps() {
        runningApps = listRunning()
        for app in runningApps {
            targetDisplayNames[app.bundleID] = app.displayName
        }
    }

    public func setName(_ name: String) {
        draft.name = name
    }

    public func setLoop(enabled: Bool, maxIterations: Int, maxDurationSeconds: Double?) {
        draft.loopEnabled = enabled
        draft.maxIterations = max(1, maxIterations)
        draft.maxDurationSeconds = maxDurationSeconds
    }

    public func addTarget(bundleID: String, displayName: String, classification: TargetAppClass) {
        targetDisplayNames[bundleID] = displayName
        let target = TargetApp(bundleID: bundleID, classification: classification)
        if !draft.targets.contains(where: { $0.bundleID == bundleID }) {
            draft.targets.append(target)
        }
    }

    public func displayName(forBundleID bundleID: String) -> String {
        if let name = targetDisplayNames[bundleID], !name.isEmpty {
            return name
        }
        if let running = runningApps.first(where: { $0.bundleID == bundleID }) {
            return running.displayName
        }
        return bundleID
    }

    public func removeTarget(at index: Int) {
        guard draft.targets.indices.contains(index) else { return }
        draft.targets.remove(at: index)
    }

    public func addStep(from item: ActionPaletteItem, activateBundleID: String = "") {
        let action = item.makeAction(activateBundleID: activateBundleID)
        let step = Step(
            action: action,
            timeoutSeconds: 2,
            retryPolicy: RetryPolicy(maxRetries: 0),
            onError: .abort
        )
        draft.steps.append(step)
    }

    public func removeStep(at index: Int) {
        guard draft.steps.indices.contains(index) else { return }
        draft.steps.remove(at: index)
    }

    public func moveStep(from: Int, to: Int) {
        guard draft.steps.indices.contains(from),
              to >= 0, to <= draft.steps.count
        else { return }
        let step = draft.steps.remove(at: from)
        let dest = from < to ? to - 1 : to
        draft.steps.insert(step, at: min(max(0, dest), draft.steps.count))
    }

    public func setWaitSeconds(at index: Int, seconds: Double) {
        guard draft.steps.indices.contains(index),
              case .wait = draft.steps[index].action
        else { return }
        draft.steps[index].action = .wait(seconds: max(0.1, seconds))
    }

    /// Validates with Config + Safety. Returns workflow if legal; does not save.
    public func validateDraft() -> Result<Workflow, WorkflowEditorError> {
        lastError = nil
        let trimmed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.emptyName)
        }
        guard !draft.targets.isEmpty else {
            return .failure(.noTargets)
        }
        guard !draft.steps.isEmpty else {
            return .failure(.noSteps)
        }

        var working = draft
        working.name = trimmed
        let workflow = working.asWorkflow()

        do {
            try validator.validate(workflow)
        } catch {
            let message = String(describing: error)
            lastError = message
            return .failure(.validation(message))
        }

        for step in workflow.steps {
            // Reject anything that mutates text (defense in depth).
            if step.action.capabilityTags.mutatesText {
                let message = "mutating actions are forbidden"
                lastError = message
                return .failure(.validation(message))
            }
            for target in workflow.targets {
                switch safety.validate(action: step.action, target: target) {
                case .allow:
                    continue
                case .deny(let reason):
                    lastError = reason
                    return .failure(.safety(reason))
                }
            }
        }

        return .success(workflow)
    }

    /// Save into the document (replace same name or append). Illegal drafts never write.
    public func save() -> Result<Workflow, WorkflowEditorError> {
        switch validateDraft() {
        case .failure(let error):
            return .failure(error)
        case .success(let workflow):
            do {
                var document: WorkflowConfigDocument
                if FileManager.default.fileExists(atPath: store.workflowsFileURL.path) {
                    document = try store.load()
                } else {
                    document = WorkflowConfigDocument(workflows: [])
                }
                if let idx = document.workflows.firstIndex(where: { $0.name == workflow.name }) {
                    document.workflows[idx] = workflow
                } else {
                    document.workflows.append(workflow)
                }
                try store.save(document)
                draft = WorkflowDraft(workflow: workflow)
                return .success(workflow)
            } catch {
                let message = String(describing: error)
                lastError = message
                return .failure(.saveFailed(message))
            }
        }
    }

    public func loadNamed(_ name: String) -> Bool {
        do {
            let document = try store.load()
            guard let workflow = document.workflows.first(where: { $0.name == name }) else {
                return false
            }
            draft = WorkflowDraft(workflow: workflow)
            return true
        } catch {
            lastError = String(describing: error)
            return false
        }
    }
}
