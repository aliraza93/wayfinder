import Domain
import Foundation

/// Maps Domain scroll directions to pixel-wheel deltas for synthesis.
public enum ScrollAction {
    /// Positive deltaY scrolls up; negative scrolls down (CG scroll-wheel convention).
    public static func deltaY(direction: ScrollDirection, amount: Int) -> Int32 {
        let magnitude = Int32(max(1, amount))
        switch direction {
        case .up: return magnitude
        case .down: return -magnitude
        case .left, .right: return 0
        }
    }
}

/// Hardcoded walking-skeleton workflow: scroll down → wait → scroll up → wait, looped.
public enum SkeletonWorkflow {
    public static let defaultIterations = 4
    public static let scrollAmount = 40
    public static let pauseSeconds = 0.45

    public static func make(
        frontmostBundleID: String,
        iterations: Int = defaultIterations
    ) -> Workflow {
        let target = TargetApp(bundleID: frontmostBundleID, classification: .generic)
        let steps: [Step] = [
            Step(
                action: .scroll(direction: .down, amount: scrollAmount),
                timeoutSeconds: 2,
                retryPolicy: RetryPolicy(maxRetries: 0),
                onError: .abort
            ),
            Step(
                action: .wait(seconds: pauseSeconds),
                timeoutSeconds: 2,
                retryPolicy: RetryPolicy(maxRetries: 0),
                onError: .abort
            ),
            Step(
                action: .scroll(direction: .up, amount: scrollAmount),
                timeoutSeconds: 2,
                retryPolicy: RetryPolicy(maxRetries: 0),
                onError: .abort
            ),
            Step(
                action: .wait(seconds: pauseSeconds),
                timeoutSeconds: 2,
                retryPolicy: RetryPolicy(maxRetries: 0),
                onError: .abort
            ),
        ]
        return Workflow(
            name: "skeleton-scroll",
            targets: [target],
            steps: steps,
            loop: LoopSettings(enabled: true, maxIterations: max(1, iterations))
        )
    }
}
