import Foundation

/// Result of the single safety gate.
public enum Decision: Equatable, Sendable {
    case allow
    case deny(reason: String)
}
