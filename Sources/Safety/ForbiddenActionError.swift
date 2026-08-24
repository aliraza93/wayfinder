import Domain
import Foundation

/// Surfaced whenever the safety gate denies an action or key. Never swallow this error.
public struct ForbiddenActionError: Error, Equatable, Sendable {
    public let action: ActionKind?
    public let target: TargetApp?
    public let keyCode: UInt16?
    public let reason: String

    public init(
        action: ActionKind? = nil,
        target: TargetApp? = nil,
        keyCode: UInt16? = nil,
        reason: String
    ) {
        self.action = action
        self.target = target
        self.keyCode = keyCode
        self.reason = reason
    }
}
