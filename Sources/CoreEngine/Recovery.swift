import Domain
import Foundation
import Safety

/// Absolute ceiling on per-step retries — `RetryPolicy.maxRetries` is clamped to this.
public enum Recovery {
    public static let absoluteMaxRetries = 3

    public static func cappedRetries(requested: Int) -> Int {
        min(max(0, requested), absoluteMaxRetries)
    }

    /// Classified failure for recovery decisions (content-free messages only).
    public enum FailureKind: Equatable, Sendable {
        case permission(String)
        case precondition(String)
        case action(String)
        case forbidden(String)
        case timeout(String)

        public var message: String {
            switch self {
            case .permission(let m), .precondition(let m), .action(let m), .forbidden(let m), .timeout(let m):
                return m
            }
        }

        /// Forbidden + permission must always abort — never skip or retry.
        public var mustAbort: Bool {
            switch self {
            case .permission, .forbidden:
                return true
            case .precondition, .action, .timeout:
                return false
            }
        }
    }

    public static func classify(_ error: Error) -> FailureKind {
        if let e = error as? ForbiddenActionError {
            return .forbidden(e.reason)
        }
        if let e = error as? PermissionError {
            return .permission(e.message)
        }
        if let e = error as? PreconditionError {
            return .precondition(e.message)
        }
        if let e = error as? TimeoutError {
            return .timeout(e.message)
        }
        if let e = error as? ActionError {
            return .action(e.message)
        }
        if let e = error as? DomainError {
            switch e {
            case .permission(let m): return .permission(m)
            case .precondition(let m): return .precondition(m)
            case .action(let m): return .action(m)
            case .forbidden(let m): return .forbidden(m)
            case .timeout(let m): return .timeout(m)
            }
        }
        return .action(String(describing: error))
    }

    /// Whether another attempt is allowed after this failure.
    public static func shouldRetry(
        kind: FailureKind,
        onError: OnErrorBehavior,
        retriesRemaining: Int
    ) -> Bool {
        if kind.mustAbort { return false }
        guard onError == .retry, retriesRemaining > 0 else { return false }
        return true
    }

    /// Outcome after a failure, respecting must-abort and on-error policy.
    public static func outcome(
        kind: FailureKind,
        onError: OnErrorBehavior,
        retriesRemaining: Int
    ) -> StepOutcome {
        if kind.mustAbort {
            return .aborted
        }
        if shouldRetry(kind: kind, onError: onError, retriesRemaining: retriesRemaining) {
            return .failed
        }
        return StepLifecycle.nextAction(onError: onError, retriesRemaining: retriesRemaining)
    }
}

/// Result of verified focus restoration at stop.
public enum FocusRestoreResult: Equatable, Sendable {
    case restored
    case couldNotRestore
}

/// Restores (or verifies) focus on the pre-run / target app after a stop.
public protocol FocusRestorer: Sendable {
    func restoreFocus(to bundleID: String) async -> FocusRestoreResult
}

/// No-op restorer for CI / when no AppKit is available.
public struct NullFocusRestorer: FocusRestorer {
    public init() {}
    public func restoreFocus(to bundleID: String) async -> FocusRestoreResult {
        _ = bundleID
        return .restored
    }
}

/// Recording restorer for tests.
public final class RecordingFocusRestorer: FocusRestorer, @unchecked Sendable {
    public private(set) var requestedBundleIDs: [String] = []
    public var result: FocusRestoreResult = .restored

    public init(result: FocusRestoreResult = .restored) {
        self.result = result
    }

    public func restoreFocus(to bundleID: String) async -> FocusRestoreResult {
        requestedBundleIDs.append(bundleID)
        return result
    }
}

/// TOCTOU / mid-run probes: re-assert focus + permission immediately before each event.
public protocol RunPreconditionProbe: Sendable {
    /// Throws `PermissionError`, `PreconditionError`, or other typed errors — never silent.
    func assertReady(for target: TargetApp) async throws
}

/// Always-ready probe (default production when platform probes are wired elsewhere).
public struct AlwaysReadyProbe: RunPreconditionProbe {
    public init() {}
    public func assertReady(for target: TargetApp) async throws {
        _ = target
    }
}

/// Scripted probe for deterministic failure injection in CI.
public final class ScriptedPreconditionProbe: RunPreconditionProbe, @unchecked Sendable {
    private var queue: [Error?]
    public private(set) var callCount = 0

    public init(failures: [Error?] = []) {
        self.queue = failures
    }

    public func assertReady(for target: TargetApp) async throws {
        _ = target
        callCount += 1
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        if let error = next {
            throw error
        }
    }
}
