import Domain
import Foundation

public enum StepLifecycle {
    /// Resolves on-error behavior after a failed/denied step given remaining retries.
    public static func nextAction(
        onError: OnErrorBehavior,
        retriesRemaining: Int
    ) -> StepOutcome {
        switch onError {
        case .retry:
            if retriesRemaining > 0 {
                return .failed // caller will retry
            }
            return .aborted
        case .skip:
            return .skipped
        case .abort:
            return .aborted
        }
    }
}
