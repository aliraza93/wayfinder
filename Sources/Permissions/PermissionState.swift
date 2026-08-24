import Foundation

/// TCC Accessibility trust state for this process.
public enum PermissionState: Equatable, Sendable {
    case unknown
    case denied
    case granted
}
