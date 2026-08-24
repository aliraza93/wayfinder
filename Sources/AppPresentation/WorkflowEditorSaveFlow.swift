import Domain
import Foundation

/// Presentation outcome of an editor save attempt (no SwiftUI).
public struct WorkflowEditorSaveFlow: Equatable, Sendable {
    public var shouldDismiss: Bool
    public var errorMessage: String?
    public var confirmationName: String?

    public init(
        shouldDismiss: Bool = false,
        errorMessage: String? = nil,
        confirmationName: String? = nil
    ) {
        self.shouldDismiss = shouldDismiss
        self.errorMessage = errorMessage
        self.confirmationName = confirmationName
    }

    public mutating func apply(result: Result<Workflow, WorkflowEditorError>) {
        switch result {
        case .success(let workflow):
            errorMessage = nil
            confirmationName = workflow.name
            shouldDismiss = true
        case .failure(let error):
            confirmationName = nil
            shouldDismiss = false
            errorMessage = Self.describe(error)
        }
    }

    public static func describe(_ error: WorkflowEditorError) -> String {
        switch error {
        case .emptyName: return "Name can’t be empty."
        case .noTargets: return "Add at least one target app."
        case .noSteps: return "Add at least one navigation step from the palette."
        case .validation(let message): return message
        case .safety(let message): return message
        case .saveFailed(let message): return "Save failed: \(message)"
        }
    }
}
