import Foundation

/// Why a run left the active loop (content-free).
public enum RunEndReason: Equatable, Sendable {
    case completed
    case stopped
    case failed
}
