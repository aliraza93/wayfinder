import Foundation

/// Injectable probe for Accessibility trust. Production uses `AXIsProcessTrustedWithOptions`.
public protocol TrustProbe: Sendable {
    /// - Parameter prompt: when `true`, may show the system permission prompt (once per denial cycle).
    func isTrusted(prompt: Bool) -> Bool
}
