import Domain
import Foundation

public enum ConfigError: Error, Equatable, Sendable {
    case unknownKey(path: String, key: String)
    case unsupportedSchemaVersion(Int)
    case missingKey(path: String, key: String)
    case invalidValue(path: String, detail: String)
    case migrationFailed(String)
    case io(String)
    case decoding(String)
    case validation(ValidationError)
}

public enum ValidationError: Error, Equatable, Sendable {
    /// An action whose capability tags disallow it for the given target class.
    case illegalActionForTarget(
        workflowName: String,
        targetClass: TargetAppClass,
        reason: String
    )
}
