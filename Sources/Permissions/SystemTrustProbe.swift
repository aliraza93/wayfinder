import ApplicationServices
import Foundation

/// Live Accessibility trust check via `AXIsProcessTrustedWithOptions`.
public struct SystemTrustProbe: TrustProbe {
    public init() {}

    public func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
