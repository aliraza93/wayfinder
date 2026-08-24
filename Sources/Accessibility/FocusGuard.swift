import CoreEngine
import Domain
import Foundation

public enum FocusGuardResult: Equatable, Sendable {
    /// Target is frontmost and remained so for the debounce window.
    case ok
    /// A different app is frontmost (or became frontmost during debounce).
    case changed
    /// No frontmost app / focus could be resolved.
    case lost
}

/// Gates synthetic input: `ok` only when the intended target is frontmost and stable.
public struct FocusGuard: Sendable {
    private let probe: any AXProbe
    private let timing: TimingPolicy
    public var debounceSeconds: TimeInterval

    public init(
        probe: any AXProbe,
        timing: TimingPolicy,
        debounceSeconds: TimeInterval = 0.15
    ) {
        self.probe = probe
        self.timing = timing
        self.debounceSeconds = debounceSeconds
    }

    /// Assert the target is frontmost and stable for `debounceSeconds`.
    public func assert(target: TargetApp) async -> FocusGuardResult {
        let expected = target.bundleID

        switch classify(current: probe.frontmostAppBundleID(), expected: expected) {
        case .lost: return .lost
        case .changed: return .changed
        case .ok:
            break
        }

        let start = timing.clock.now
        let stable = await timing.wait(timeoutSeconds: debounceSeconds) {
            let current = self.probe.frontmostAppBundleID()
            let elapsed = self.timing.clock.now.timeIntervalSince(start) >= self.debounceSeconds
            let stillTarget = current == expected
            return elapsed && stillTarget
        }

        if !stable {
            return classify(current: probe.frontmostAppBundleID(), expected: expected)
        }

        // Final check after debounce window.
        return classify(current: probe.frontmostAppBundleID(), expected: expected)
    }

    private func classify(current: String?, expected: String) -> FocusGuardResult {
        guard let current, !current.isEmpty else {
            return .lost
        }
        if current == expected {
            return .ok
        }
        return .changed
    }
}
