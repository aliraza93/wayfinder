import Foundation

/// Content-free run outcome. Never carries free-form app content.
public enum RunEventResult: String, Equatable, Sendable {
    case completed
    case failed
    case denied
    case skipped
}

/// Exactly the allowed log fields: timestamp, actionKind, targetBundleID, result.
public struct RunEvent: Equatable, Sendable {
    public var timestamp: Date
    public var actionKind: String
    public var targetBundleID: String
    public var result: RunEventResult

    public init(
        timestamp: Date,
        actionKind: String,
        targetBundleID: String,
        result: RunEventResult
    ) {
        self.timestamp = timestamp
        self.actionKind = actionKind
        self.targetBundleID = targetBundleID
        self.result = result
    }
}
