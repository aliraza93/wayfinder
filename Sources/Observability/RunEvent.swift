import Foundation

/// Content-free run outcome. Never carries free-form app content.
public enum RunEventResult: String, Equatable, Sendable {
    case completed
    case failed
    case denied
    case skipped
}

/// Exactly the allowed log fields, plus optional user-configured identity (never body text).
public struct RunEvent: Equatable, Sendable {
    public var timestamp: Date
    public var actionKind: String
    public var targetBundleID: String
    public var result: RunEventResult
    /// Relative file path or tab label the user configured — never document/page body.
    public var identity: String?

    public init(
        timestamp: Date,
        actionKind: String,
        targetBundleID: String,
        result: RunEventResult,
        identity: String? = nil
    ) {
        self.timestamp = timestamp
        self.actionKind = actionKind
        self.targetBundleID = targetBundleID
        self.result = result
        self.identity = identity
    }
}
