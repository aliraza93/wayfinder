import Foundation

/// Accessibility / TCC permission failure. Never swallow — stop the run.
public struct PermissionError: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) {
        self.message = message
    }
}

/// Precondition failed (Secure Input, focus not stable, app quit). Do not retry/loop.
public struct PreconditionError: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) {
        self.message = message
    }
}

/// Action execution failed for a non-forbidden reason.
public struct ActionError: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) {
        self.message = message
    }
}

/// Step or wait exceeded its timeout.
public struct TimeoutError: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) {
        self.message = message
    }
}
