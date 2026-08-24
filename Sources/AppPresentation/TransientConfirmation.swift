import Foundation

/// Transient green confirmation shown after a successful workflow save.
/// Expiry is evaluated via `refresh()` against an injectable clock (no wall sleep in tests).
public final class TransientConfirmation: @unchecked Sendable {
    public private(set) var message: String?
    private var expiresAt: Date?
    private let duration: TimeInterval
    private let now: () -> Date

    public init(durationSeconds: TimeInterval = 2.5, now: @escaping () -> Date = { Date() }) {
        self.duration = durationSeconds
        self.now = now
    }

    public func showSaved(workflowName: String) {
        message = "Saved '\(workflowName)'"
        expiresAt = now().addingTimeInterval(duration)
    }

    /// Clears the message when the clock has passed `expiresAt`. Returns current message.
    @discardableResult
    public func refresh() -> String? {
        if let expiresAt, now() >= expiresAt {
            message = nil
            self.expiresAt = nil
        }
        return message
    }

    public func clear() {
        message = nil
        expiresAt = nil
    }
}
