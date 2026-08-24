import Domain
import Foundation

/// Validates workflows against capability tags and target classifications.
public struct WorkflowValidator: Sendable {
    private let tagsFor: @Sendable (ActionKind) -> CapabilityTags

    public init(tagsFor: @escaping @Sendable (ActionKind) -> CapabilityTags = { $0.capabilityTags }) {
        self.tagsFor = tagsFor
    }

    public func validate(_ workflow: Workflow) throws {
        for step in workflow.steps {
            let tags = tagsFor(step.action)
            for target in workflow.targets {
                try validate(action: step.action, tags: tags, target: target, workflowName: workflow.name)
            }
        }
    }

    public func validate(document: WorkflowConfigDocument) throws {
        for workflow in document.workflows {
            try validate(workflow)
        }
    }

    private func validate(
        action: ActionKind,
        tags: CapabilityTags,
        target: TargetApp,
        workflowName: String
    ) throws {
        // Read-only invariant for every target class (editors included).
        if tags.mutatesText {
            let reason: String
            if target.classification == .editor {
                reason = "editor targets may only carry mutatesText == false actions"
            } else {
                reason = "action mutatesText=true is forbidden for \(target.classification)"
            }
            throw ConfigError.validation(
                .illegalActionForTarget(
                    workflowName: workflowName,
                    targetClass: target.classification,
                    reason: reason
                )
            )
        }

        _ = action
    }
}
